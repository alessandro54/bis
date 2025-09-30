import os
import asyncio
import json
import time
import random
import base64
import httpx
from typing import TypedDict
from app.core.config import settings
from app.core.redis_client import get_redis_async
from redis.asyncio import Redis


class BlizzardToken(TypedDict):
    access_token: str
    expires_at: float


TOKEN_HOST: dict[str, str] = {
    "us": "https://us.battle.net",
    "eu": "https://eu.battle.net",
    "kr": "https://kr.battle.net",
    "tw": "https://tw.battle.net",
}


def _token_key(region: str) -> str:
    return f"oauth:blizzard:{region.lower()}"


def _lock_key(region: str) -> str:
    return f"lock:oauth:blizzard:{region.lower()}"


def _backoff(attempt: int = 0) -> float:
    base = min(settings.OAUTH_BACKOFF_BASE * (2**attempt), 10.0)
    return random.uniform(0.5 * base, 1.0 * base)


async def get_token(region: str = "us") -> str:
    if not settings.BLIZZARD_CLIENT_ID or not settings.BLIZZARD_CLIENT_SECRET:
        raise ValueError("Blizzard client ID and secret must be set")

    region = region.lower()
    r = await get_redis_async()
    token = await _read_token(r, region)
    now = time.time()

    if token:
        expires_at = token.get("expires_at") - now
        if expires_at > settings.OAUTH_REFRESH_LEEWAY:
            return token.get("access_token")
        if expires_at > 0:
            _ = asyncio.create_task(_refresh_if_possible(region))
            return token.get("access_token")

    await _refresh_blocking(region)
    token = await _read_token(r, region)
    if not token:
        raise RuntimeError("Failed to obtain Blizzard OAuth token")
    return token.get("access_token")


async def _refresh_if_possible(region: str) -> None:
    try:
        await _refresh_blocking(region, nonblocking=True)
    except Exception:
        pass


async def _refresh_blocking(region: str, nonblocking: bool = False) -> None:
    r = await get_redis_async()
    lock_key = _lock_key(region)
    lock_val = f"{os.getpid()}-{random.randint(1000, 9999)}-{time.time()}"

    got_lock = await r.set(lock_key, lock_val, nx=True, ex=settings.OAUTH_LOCK_TTL)
    if not got_lock:
        if nonblocking:
            return
        for _ in range(5):
            await asyncio.sleep(_backoff())
            tok = await _read_token(r, region)
            if tok and (tok["expires_at"] - time.time()) > 0:
                return
        got_lock = await r.set(lock_key, lock_val, nx=True, ex=settings.OAUTH_LOCK_TTL)
        if not got_lock:
            tok = await _read_token(r, region)
            if not tok or tok["expires_at"] <= time.time():
                raise RuntimeError(
                    "Token refresh contention and no valid token available"
                )
            return

    try:
        await _fetch_and_store(region)
    finally:
        try:
            cur = await r.get(lock_key)
            if cur == lock_val:
                await r.delete(lock_key)
        except Exception:
            pass


async def _fetch_and_store(region: str) -> None:
    host = TOKEN_HOST.get(region.lower())
    if not host:
        raise ValueError(f"Unsupported region: {region}")

    url = f"{host}/oauth/token"
    data = {"grant_type": "client_credentials"}
    basic = base64.b64encode(
        f"{settings.BLIZZARD_CLIENT_ID}:{settings.BLIZZARD_CLIENT_SECRET}".encode()
    ).decode()
    headers = {"Authorization": f"Basic {basic}"}

    last_err: Exception | None = None
    for attempt in range(settings.OAUTH_MAX_RETRIES):
        try:
            async with httpx.AsyncClient(timeout=settings.OAUTH_HTTP_TIMEOUT) as client:
                resp = await client.post(url, data=data, headers=headers)
            if resp.status_code == 200:
                j = resp.json()
                access = j["access_token"]
                expires_in = int(j.get("expires_in", 0))
                expires_at = time.time() + max(
                    0, expires_in - settings.OAUTH_CLOCK_SKEW
                )
                ttl = max(1, int(expires_at - time.time()))
                r = await get_redis_async()
                await r.set(
                    _token_key(region),
                    json.dumps({"access_token": access, "expires_at": expires_at}),
                    ex=ttl,
                )
                return
            if resp.status_code in (429, 500, 502, 503, 504):
                await asyncio.sleep(_backoff(attempt))
                continue
            resp.raise_for_status()
        except Exception as e:
            last_err = e
            await asyncio.sleep(_backoff(attempt))
    raise RuntimeError(f"Blizzard token refresh failed: {last_err}")


async def _read_token(r: Redis, region: str) -> BlizzardToken | None:
    raw = await r.get(_token_key(region))
    if not raw:
        return None
    try:
        obj = json.loads(raw)
        if "access_token" in obj and "expires_at" in obj:
            return obj
    except Exception:
        await r.delete(_token_key(region))
        return None

    at = obj.get("access_token")
    exp = obj.get("expires_at")
    if not isinstance(at, str) or not isinstance(exp, (int, float)):
        await r.delete(_token_key(region))
        return None

    if exp <= time.time():
        await r.delete(_token_key(region))
        return None
    return BlizzardToken(access_token=at, expires_at=float(exp))

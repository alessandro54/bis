from typing import Any
import httpx

from etl.blizzard.auth.oauth import get_token


HOSTS: dict[str, str] = {
    "us": "https://us.api.blizzard.com",
    "eu": "https://eu.api.blizzard.com",
    "kr": "https://kr.api.blizzard.com",
    "tw": "https://tw.api.blizzard.com",
    "cn": "https://gateway.battlenet.com.cn",
}

async def blizzard_get(
        region: str,
        path: str,
        params: dict[str, Any] | None = None,
        timeout: float = 20.0,
) -> httpx.Response:
    base_url = HOSTS.get(region)
    if not base_url:
        raise ValueError(f"Unsupported region: {region}")

    token = await get_token(region)

    headers = {
        "Authorization": f"Bearer {token}"
    }

    async with httpx.AsyncClient(timeout=timeout) as client:
        url = f"{base_url}{path}"
        return await client.get(url, headers=headers, params=params or {})

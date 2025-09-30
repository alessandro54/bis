from app.core.config import settings
import asyncio
from redis import Redis as RedisSync
import redis.asyncio as aioredis

__redis_async: aioredis.Redis | None = None
__redis_sync: RedisSync | None = None
__lock = asyncio.Lock()


def get_redis_sync() -> RedisSync:
    global __redis_sync
    if __redis_sync is None:
        __redis_sync = RedisSync.from_url(
            settings.REDIS_URL,
            decode_responses=True,
            max_connections=settings.REDIS_MAX_CONNECTIONS,
        )
    return __redis_sync


async def get_redis_async() -> aioredis.Redis:
    global __redis_async
    if __redis_async is not None:
        return __redis_async
    async with __lock:
        if __redis_async is None:
            __redis_async = aioredis.from_url(
                settings.REDIS_URL,
                decode_responses=True,
                max_connections=settings.REDIS_MAX_CONNECTIONS,
            )
        return __redis_async


def ping_sync() -> bool:
    try:
        return bool(get_redis_sync().ping())
    except Exception:
        return False

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    DATABASE_URL: str = ""
    REDIS_URL: str = ""
    REDIS_MAX_CONNECTIONS: int = 20

    BLIZZARD_CLIENT_ID: str = ""
    BLIZZARD_CLIENT_SECRET: str = ""

    OAUTH_REFRESH_LEEWAY: int = 60
    OAUTH_CLOCK_SKEW: int = 5
    OAUTH_LOCK_TTL: int = 20
    OAUTH_MAX_RETRIES: int = 5
    OAUTH_BACKOFF_BASE: float = 0.75
    OAUTH_HTTP_TIMEOUT: float = 20.0

    class Config:
        env_file = ".env"
        extra = "ignore"


settings = Settings()

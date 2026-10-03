# 2026-10-02 — settings pydantic obligatoires (convention vusine-dev :
# l'application REFUSE de démarrer si une variable critique manque ou est trop courte).
from functools import lru_cache
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    APP_NAME: str = "EVALPOINT API"
    # --- base PostgreSQL (dev : ratingdb_dev / rôle postgres) ---
    POSTGRES_HOST: str = "localhost"
    POSTGRES_PORT: int = 5432
    POSTGRES_DB: str = "ratingdb_dev"
    POSTGRES_USER: str = "postgres"
    POSTGRES_PASSWORD: str = ""

    # --- sécurité (exigences dures) ---
    AUTH_SECRET_KEY: str                      # obligatoire, >= 32 caractères
    ACCESS_TOKEN_TTL_MINUTES: int = 720       # 12 h (convention)
    LOGIN_MAX_FAILURES: int = 5               # throttle : 5 échecs
    LOGIN_LOCK_MINUTES: int = 15              # ... par 15 minutes

    # --- divers ---
    CORS_ORIGINS: str = "http://localhost:5176"  # séparées par des virgules ; vide en prod
    SCHEDULERS_ENABLED: bool = False           # APScheduler désactivé par défaut

    # Configuration pour charger automatiquement le fichier .env
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore"
    )

    @property
    def sqlalchemy_url(self) -> str:
        return (
            f"postgresql+psycopg2://{self.POSTGRES_USER}:{self.POSTGRES_PASSWORD}"
            f"@{self.POSTGRES_HOST}:{self.POSTGRES_PORT}/{self.POSTGRES_DB}"
        )

    @property
    def cors_list(self) -> list[str]:
        return [o.strip() for o in self.CORS_ORIGINS.split(",") if o.strip()]


class InvalidSettings(Exception):
    pass


@lru_cache
def get_settings() -> Settings:
    s = Settings()  # lève une erreur pydantic si .env incomplet -> refus de démarrer
    if len(s.AUTH_SECRET_KEY) < 32:
        raise InvalidSettings("AUTH_SECRET_KEY doit faire au moins 32 caractères.")
    return s
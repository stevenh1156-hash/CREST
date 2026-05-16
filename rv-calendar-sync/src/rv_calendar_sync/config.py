from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_prefix="RV_SYNC_",
        extra="ignore",
    )

    db_path: Path = Path("./data/rv_sync.sqlite")
    host: str = "0.0.0.0"
    port: int = 8000
    public_base_url: str = "http://localhost:8000"
    admin_token: str = "change-me"
    interval_minutes: int = 15

    wix_api_key: str = ""
    wix_site_id: str = ""
    wix_account_id: str = ""


_settings: Settings | None = None


def get_settings() -> Settings:
    global _settings
    if _settings is None:
        _settings = Settings()
        _settings.db_path.parent.mkdir(parents=True, exist_ok=True)
    return _settings

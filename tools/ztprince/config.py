from pydantic_settings import BaseSettings,SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "ZTPrince"
    netbox_url: str
    netbox_token: str
    cvAddr: str
    enrollmentToken: str
    ntpServer: str

    model_config = SettingsConfigDict(
        env_file='.env',
        env_file_encoding='utf-8'
    )

settings = Settings()

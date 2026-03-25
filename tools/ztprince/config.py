from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    app_name: str = "ZTPrince"
    netbox_url: str
    netbox_token: str

settings = Settings()

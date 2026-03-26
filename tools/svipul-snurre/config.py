from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    app_name: str = "svipul snurre to send orders to svipul"
    svipul_add_job_path: str
    netbox_url: str
    netbox_token: str
    broker_url: str = "amqp://guest:guest@localhost:5672/"
    queue_name: str = "svipul"

settings = Settings()

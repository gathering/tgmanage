import pynetbox

from fastapi import FastAPI, Response
from fastapi.responses import PlainTextResponse
from jinja2 import Environment, PackageLoader, select_autoescape

env = Environment(
    loader=PackageLoader("ztprince"),
    autoescape=select_autoescape()
)

from .config import settings


app = FastAPI()

nb = pynetbox.api(
    settings.netbox_url,
    token=settings.netbox_token,
    threading=True,
)


@app.get("/")
def read_root():
    return {"Hello": "World"}


@app.get("/ztp/{hostname}")
def read_item(hostname: str, response: Response):
    device = nb.dcim.devices.get(name=hostname)
    if not device:
        response.status_code = 404
        return
    config = device.render_config.create()
    return PlainTextResponse(content=config['content'])

@app.get("/arista-ztp/")
def read_item(response: Response):
    bootstrap = env.get_template("bootstrap_template.j2")
    return PlainTextResponse(content=bootstrap.render(cvAddr=settings.cvAddr,
        enrollmentToken=settings.enrollmentToken,
        ntpServer=settings.ntpServer))
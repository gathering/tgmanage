import logging
import netaddr
import pika
import pynetbox
import schedule
import threading
import time

from pynetbox.core.query import json
import fastuuid

from config import settings


logger = logging.getLogger(__name__)

nb = pynetbox.Api(settings.netbox_url, token=settings.netbox_token, threading=True)
rabbit = pika.BlockingConnection(pika.ConnectionParameters(settings.broker_url))
rabbit_channel = rabbit.channel()

devices = []

def get_devices():
    print("Loading devices from netbox")
    global devices

    updated_devices = nb.dcim.devices.filter(status="active")
    devices = updated_devices

def read_pollconf():
    j = {}
    with open('polling.json', 'r') as f:
        content = f.read()
        try:
            j = json.loads(content)
        except Exception as e:
            print(f'failed to load polling config: {e}')
            return None
    return j

def create_order(target: str, id=None, mode="Get", oids=['sysName.0'], elements=[]):
    if id is None:
        id = str(fastuuid.uuid7())
    return {
        'target': str(target),
        'mode': mode,
        'oids': oids,
        'id': id,
        'elements': elements,
    }

def send_order(order):
    rabbit_channel.basic_publish(exchange='', routing_key=settings.queue_name, body=json.dumps(order))


def main():
    print("Hello from svipul-snurre!")

    pollconf = {}

    while True:
        new_pollconf = read_pollconf()
        # if it fails to load, keep using the old conf
        if new_pollconf:
            pollconf = new_pollconf

        second_polls = []
        for device in devices:
            if not device.primary_ip:
                logger.debug(f'Skipping {device.name} because it has no primary ip')
                continue
            addrs = []
            if device.primary_ip4:
                addr = netaddr.IPNetwork(device.primary_ip4.address)
                addrs.append(addr)
            if device.primary_ip6:
                addr = netaddr.IPNetwork(device.primary_ip6.address)
                addrs.append(addr)

            for addr in addrs:
                send_order(create_order(addr.ip, id=f'{device.name};system', mode='Get', oids=pollconf['system_oids']))
                second_polls.append(create_order(addr.ip, id=f'{device.name};ports', mode='GetElements', oids=pollconf['ports_oids'], elements=['.*']))

            print("poll system", device)

        time.sleep(1)

        print("poll ports")
        for order in second_polls:
            send_order(order)

        time.sleep(10)

def start_device_updater():
    while True:
        schedule.run_pending()


if __name__ == "__main__":
    get_devices()
    schedule.every(5).minutes.do(get_devices)
    t = threading.Thread(target=start_device_updater, daemon=True)
    main()
    rabbit.close()

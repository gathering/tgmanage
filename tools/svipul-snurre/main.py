import logging
import netaddr
import pika
import pynetbox
import time

from pynetbox.core.query import json
import fastuuid

from config import settings


logger = logging.getLogger(__name__)

nb = pynetbox.Api(settings.netbox_url, token=settings.netbox_token, threading=True)
rabbit = pika.BlockingConnection(pika.ConnectionParameters(settings.broker_url))
rabbit_channel = rabbit.Channel()


def create_order(target: str, mode="Get", oids=['sysName.0']):
    id = fastuuid.uuid7()
    return {
        'target': target,
        'mode': mode,
        'oids': oids,
        'id': id,
    }

def send_order(order):
    rabbit_channel.basic_publish(exchange='', routing_key=settings.queue_name, body=json.dums(order))


def main():
    print("Hello from svipul-snurre!")

    while True:
        orders = []

        devices = nb.dcim.devices.filter(status="active")
        for device in devices:
            if not device.primary_ip:
                logger.debug(f'Skipping {device.name} because it has no primary ip')
                continue
            if device.primary_ip4:
                addr = netaddr.IPNetwork(device.primary_ip4.address)
                send_order(create_order(addr.ip))
            if device.primary_ip6:
                addr = netaddr.IPNetwork(device.primary_ip6.address)
                send_order(create_order(addr.ip))

            print("poll", device)


        time.sleep(10)

    rabbit.close()


if __name__ == "__main__":
    main()

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
rabbit_channel = rabbit.channel()


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

    while True:
        devices = nb.dcim.devices.filter(status="active")
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
                send_order(create_order(addr.ip, id='system', mode='Get', oids=system_oids))
                send_order(create_order(addr.ip, id='ports', mode='GetElements', oids=ports_oids, elements=['.*']))

            print("poll", device)


        time.sleep(10)


ports_oids = ["ifAdminStatus", "ifDescr", "ifInDiscards", "ifInErrors", "ifInNUcastPkts", "ifInOctets", "ifInUcastPkts", "ifInUnknownProtos", "ifIndex", "ifLastChange", "ifMtu", "ifOperStatus", "ifOutDiscards", "ifOutErrors", "ifOutNUcastPkts", "ifOutOctets", "ifOutQLen", "ifOutUcastPkts", "ifPhysAddress", "ifSpecific", "ifSpeed", "ifType"]
system_oids = [
    "sysUpTime.0",
    "sysName.0",
    "sysDescr.0",
    "entPhysicalSerialNum.0",
    "sysUpTime.0",
    "sysName.0",
    "sysDescr.0",
    "entPhysicalSerialNum.0",
]

if __name__ == "__main__":
    main()
    rabbit.close()

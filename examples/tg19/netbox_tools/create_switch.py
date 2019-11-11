#!/usr/bin/python3

import pynetbox
import ipaddress
import re

import pyargs
import argparse

parser = argparse.ArgumentParser()
parser.add_argument('-name')
parser.add_argument('-vlanid')
parser.add_argument('-intf', nargs='+')

args = parser.parse_args()

nb = pynetbox.api(
    'https://netbox.infra.gathering.org',
    token='<Removed>'
)


RING_SITE = 2
RING_DEVICE_ID = 15
RING_VLAN_GROUP = 1
RING_NAME = 'r1.ring'
RING_MGMT_v4_PREFIX = 486
RING_MGMT_V6_PREFIX_ID = 118
RING_MGMT_V6_PREFIX = "2a06:5841:c:"

RING_PREFIX_SUPERNET_v4 = 28
RING_PREFIX_SUPERNET_v6 = 105

EDGE_DEVICE_TYPE = 5
EDGE_DEVICE_ROLE = 11
EDGE_VLAN_ROLE = 1
EDGE_LAG_NAME = 'ae0'
EDGE_MGMT_INTF_NAME = 'vlan.666'
EDGE_DEVICE_PLATFORM = 3
EDGE_UPLINKS = ['ge-0/0/47', 'ge-0/0/46']

sysname = args.name

vlanid = args.vlanid
dist_interfaces = args.intf

print('Creating VLAN {} with ID {}'.format(sysname, vlanid))
vlan = nb.ipam.vlans.create(
    name=sysname,
    vid=vlanid,
    status=1,
    site=RING_SITE,
    group=RING_VLAN_GROUP,
    role=EDGE_VLAN_ROLE
)

nb.ipam.prefixes.get(RING_PREFIX_SUPERNET_v4).available_prefixes.create({
    "prefix_length": 26,
    "vlan": vlan.id,
    "site": RING_SITE,
    "role": EDGE_VLAN_ROLE,
    "description": sysname
    })
v4_prefix = nb.ipam.prefixes.get(vlan_id=vlan.id, family=4, status=1)
print('Created Prefix {}'.format(v4_prefix))

nb.ipam.prefixes.create(
    family = 6,
    prefix = RING_MGMT_V6_PREFIX + str(vlan.vid) + "::/64",
    vlan = vlan.id,
    status = 1,
    site = RING_SITE,
    role = EDGE_VLAN_ROLE,
    description = sysname
)
v6_prefix = nb.ipam.prefixes.get(vlan_id=vlan.id, family=6, status=1)
print('Created Prefix {}'.format(v6_prefix))

print('Creating Device {}'.format(sysname))
switch = nb.dcim.devices.create(
    name = sysname,
    device_type = EDGE_DEVICE_TYPE,
    device_role = EDGE_DEVICE_ROLE,
    platform = EDGE_DEVICE_PLATFORM,
    site = RING_SITE,
    status = 1
)

ae_interface = nb.dcim.interfaces.get(device_id=switch.id, name=EDGE_LAG_NAME)
mgmt_interface = nb.dcim.interfaces.get(device_id=switch.id, name=EDGE_MGMT_INTF_NAME)
ring_ae_interface = nb.dcim.interfaces.create(
    device = RING_DEVICE_ID,
    name = "ae" + vlanid,
    form_factor = 200,
    description = sysname
)

ring_irb_interface = nb.dcim.interfaces.create(
    device = RING_DEVICE_ID,
    name = "irb." + vlanid,
    form_factor = 200,
    description = sysname
)
ring_ipv4 = nb.ipam.ip_addresses.create(
    interface = ring_irb_interface.id,
    address = v4_prefix.available_ips.list()[1]['address'],
    status = 1,
    description = sysname
)
ring_ipv6 = nb.ipam.ip_addresses.create(
    interface = ring_irb_interface.id,
    address = v6_prefix.available_ips.list()[1]['address'],
    status = 1,
    description = sysname
)

for x, uplinks in enumerate(EDGE_UPLINKS):
    uplink = nb.dcim.interfaces.get(device_id=switch.id, name=uplinks)
    uplink.lag = ae_interface.id
    uplink.save()
    intf = nb.dcim.interfaces.get(device_id=RING_DEVICE_ID, name=dist_interfaces[x-1])
    print('Creating cable {}:{} -> {}:{}'.format(RING_NAME, intf, sysname, uplink))
    nb.dcim.cables.create(
        termination_a_id = intf.id,
        termination_a_type = 'dcim.interface',
        termination_b_id = uplink.id,
        termination_b_type = 'dcim.interface',
        status = True,
        color = 'c0c0c0'
    )

for x, interfaces in enumerate(dist_interfaces):
    interface = nb.dcim.interfaces.get(device_id=RING_DEVICE_ID, name=interfaces)
    interface.lag = ring_ae_interface.id
    interface.save()

mgmt_interface = nb.dcim.interfaces.get(device_id=switch.id, name=EDGE_MGMT_INTF_NAME)

mgmt_v4_address = nb.ipam.prefixes.get(RING_MGMT_v4_PREFIX).available_ips.list()[0]['address']
mgmt_v6_address = nb.ipam.prefixes.get(RING_MGMT_V6_PREFIX_ID)
ipv4 = nb.ipam.ip_addresses.create(
    interface = mgmt_interface.id,
    address = "{}".format(str(mgmt_v4_address)),
    status = 1,
    description = sysname
)

p = re.compile('(.*)\.(.*)\.(.*)\.(.*)/(.*)')
m = p.match(mgmt_v4_address)
ipv4_last = m.group(4)
print(str(mgmt_v6_address))
p = re.compile('(.*)::/(.*)')
m = p.match(str(mgmt_v6_address))

ipv6 = nb.ipam.ip_addresses.create(
    interface = mgmt_interface.id,
    address = "{0}::{1}/64".format(m.group(1), ipv4_last),
    status = 1,
    description = sysname
)
switch.primary_ip4 = ipv4.id
switch.primary_ip6 = ipv6.id
switch.save()

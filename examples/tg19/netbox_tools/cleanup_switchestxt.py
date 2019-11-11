#!/usr/bin/python3

import pynetbox
import ipaddress
import re
from natsort import natsorted

nb = pynetbox.api(
    'https://netbox.infra.gathering.org',
    token='<Removed>'
)

FLOOR_SITE = 4
CORE_DEVICE_ID = 16
CORE_NAME = 'r1.noc'
CORE_DISTRO_PORTS = ['xe-0/2/{}', 'xe-0/3/{}']

DISTRO_DEVICE_TYPE = 7
DISTRO_DEVICE_ROLE = 8
DISTRO_MGMT_VLAN_ROLE = 4
DISTRO_MGMT_VLAN_ID = 666
DISTRO_UPLINK_AE = 'ae0'
DISTRO_UPLINK_PORTS = ['xe-0/1/0', 'xe-1/1/0']
DISTRO_DEVICE_PLATFORM = 3
DISTRO_LINKNET_VLAN_ID = 888
DISTRO_LINKNET_ROLE = 3


EDGE_DEVICE_TYPE = 5
EDGE_DEVICE_ROLE = 10
EDGE_VLAN_ROLE = 2
EDGE_LAG_NAME = 'ae0'
EDGE_DEVICE_PLATFORM = 3

LOOPBACK_POOL_V4_ID = 10
LOOPBACK_POOL_V6_ID = 121

LINKNET_POOL_V4_ID = 11
LINKNET_POOL_V6_ID = 124

with open('switches.txt') as f:
    switchestxt = f.readlines()
with open('patchlist.txt') as f:
     patchlisttxt = f.readlines()

nb_vlans = nb.ipam.vlans.filter(site_id = FLOOR_SITE)
nb_prefixes = nb.ipam.prefixes.filter(site_id = FLOOR_SITE)
nb_switches = nb.dcim.devices.filter(site_id = FLOOR_SITE)

switches = {}
distros = {}

def cleanupswitchandnetwork(sw, site_id):
    name = sw['sysname']
    network_name = name

    network = None
    for vlan in nb_vlans:
        if vlan.name == network_name:
            network = vlan
            break

    prefix_v4 = None
    prefix_v6 = None

    for prefix in nb_prefixes:
        if prefix.vlan is not None and prefix.vlan.id == network.id and prefix.family == 4:
            prefix_v4 = prefix
        if prefix.vlan is not None and prefix.vlan.id == network.id and prefix.family == 6:
            prefix_v6 = prefix

        if prefix_v4 and prefix_v6 is not None:
            break

    if prefix_v4 is not None:
        print('Deleting Prefix {}'.format(sw['subnet4']))
        prefix_v4.delete()

    if prefix_v6 is not None:
        print('Deleting Prefix {}'.format(sw['subnet6']))
        prefix_v6.delete()

    if network is None:
        print('Deleting Network {}'.format(network_name))
        network.delete()

    switch = None
    for device in nb_switches:
        if device.name == name:
            switch = device
            break
    if switch is not None:
        print('Deleting Switch {}'.format(name))
        switch.delete()

    if sw['is_distro'] is False: # Edge switch that have a distro
        distro_id = nb.dcim.devices.get(name=sw['distro_name']).id
        mgmt_network = nb.ipam.vlans.get(name="mgmt.{}".format(sw['distro_name']))
        ae_interface = nb.dcim.interfaces.get(device_id=switch.id, name=sw['lag_name'])
        if ae_interface is not None:
            print('Deleting {} for {}'.format(sw['lag_name'], name))
            ae_interface.delete()
        distro_ae_interface_name = 'ae{}'.format(sw['vlan_id'])
        distro_ae_interface = nb.dcim.interfaces.get(device_id=distro_id, name=distro_ae_interface_name)
        if distro_ae_interface is not None:
            print('Deleting {} for {}'.format(distro_ae_interface_name,sw['distro_name']))
            distro_ae_interface.delete()

        distro_x = int(re.match('s(.*)\.floor', sw['distro_name']).group(1))
        core_subif_name = 'ae{}.{}'.format(distro_x + 10,sw['vlan_id'])
        core_subif_interface = nb.dcim.interfaces.get(device_id = sw['core_device_id'], name = core_subif_name)
        if core_subif_interface is not None:
            print('Deleting {} for core {}'.format(core_subif_name, sw['core_name']))
            core_subif_interface.delete()

for switch in switchestxt:
    switch = switch.strip().split()
    switches[switch[0]] = {
        'sysname': switch[0],
        'subnet4': switch[1],
        'subnet6': switch[2],
        'mgmt4': switch[3],
        'mgmt6': switch[4],
        'vlan_id': int(switch[5]),
        'distro_name': switch[6],
        'is_distro': False,
        'vlan_role_id': EDGE_VLAN_ROLE,
        'device_type_id': EDGE_DEVICE_TYPE,
        'device_role_id': EDGE_DEVICE_ROLE,
        'device_platform_id': EDGE_DEVICE_PLATFORM,
        'lag_name': EDGE_LAG_NAME,
        'core_device_id': CORE_DEVICE_ID,
        'core_name': CORE_NAME
    }

for patch in patchlisttxt:
    patch = patch.strip().split()
    uplink = []
    for p in patch[2:]:
        uplink.append(p)
    switches[patch[0]].update({
        'uplinks': uplink
    })

print('Access started')
for switch in natsorted(switches):
    sw = switches[switch]
    cleanupswitchandnetwork(sw, FLOOR_SITE)
print('Access done')

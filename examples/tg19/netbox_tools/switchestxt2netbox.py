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

def createswitchandnetwork(sw, site_id):
    name = sw['sysname']
    network_name = name
    if sw['is_distro']:
        network_name = 'mgmt.{}'.format(name)

    network = None
    for vlan in nb_vlans:
        if vlan.name == network_name:
            if vlan.vid != sw['vlan_id']:
                print("Vlan with name {} already exist, but have wrong vlan ID {}".format(vlan.name, vlan.vid))
                exit(1)
            network = vlan
            break

    if network is None:
        print('Creating Network {}'.format(network_name))
        network = nb.ipam.vlans.create(
            name=network_name,
            vid=sw['vlan_id'],
            status=1,
            site=site_id,
            role=sw['vlan_role_id']
        )

    prefix_v4 = None
    prefix_v6 = None

    for prefix in nb_prefixes:
        if prefix.vlan is not None and prefix.vlan.id == network.id and prefix.family == 4:
            prefix_v4 = prefix
        if prefix.vlan is not None and prefix.vlan.id == network.id and prefix.family == 6:
            prefix_v6 = prefix

        if prefix_v4 and prefix_v6 is not None:
            break

    if prefix_v4 is None:
        print('Creating Prefix {}'.format(sw['subnet4']))
        prefix_v4 = nb.ipam.prefixes.create(
            family = 4,
            prefix = sw['subnet4'],
            vlan = network.id,
            status = 1,
            site = site_id,
            role = sw['vlan_role_id']
        )

    if prefix_v6 is None:
        print('Creating Prefix {}'.format(sw['subnet6']))
        prefix_v6 = nb.ipam.prefixes.create(
            family = 6,
            prefix = sw['subnet6'],
            vlan = network.id,
            status = 1,
            site = FLOOR_SITE,
            role = sw['vlan_role_id']
        )

    switch = None
    for device in nb_switches:
        if device.name == name:
            switch = device
            break
    if switch is None:
        print('Creating Switch {}'.format(name))
        switch = nb.dcim.devices.create(
            name = name,
            device_type = sw['device_type_id'],
            device_role = sw['device_role_id'],
            platform = sw['device_platform_id'],
            site = FLOOR_SITE,
            status = 1
        )

    if sw['is_distro'] is True: # Distro
        if nb.dcim.interfaces.get(device_id=switch.id, name='lo0') is None:
            print('Creating lo0 for {}'.format(name))
            lo_interface = nb.dcim.interfaces.create(
                device = switch.id,
                name = 'lo0',
                form_factor = 0,
                description = "{} loopback".format(name)
            )
            loopback_v4_address = nb.ipam.prefixes.get(sw['loopback_pool_v4_id']).available_ips.list()[0]['address']
            print("{}/32".format(str(ipaddress.ip_interface(loopback_v4_address).ip)))
            ipv4 = nb.ipam.ip_addresses.create(
                interface = lo_interface.id,
                address = "{}/32".format(str(ipaddress.ip_interface(loopback_v4_address).ip)),
                status = 1,
                description = "{} loopback".format(name),
                role = 10
                )

            loopback_v6_address = nb.ipam.prefixes.get(sw['loopback_pool_v6_id'])
            p = re.compile('(.*)\.(.*)\.(.*)\.(.*)/(.*)')
            m = p.match(loopback_v4_address)
            ipv4_last = m.group(4)
            print(str(loopback_v6_address))
            p = re.compile('(.*)::/(.*)')
            m = p.match(str(loopback_v6_address))

            ipv6 = nb.ipam.ip_addresses.create(
                interface = lo_interface.id,
                address = "{0}::{1}/128".format(m.group(1), ipv4_last),
                status = 1,
                description = "{} loopback".format(name),
                role = 10
                )
            switch.primary_ip4 = ipv4.id
            switch.primary_ip6 = ipv6.id
            switch.save()

        mgmt_interface_name = 'vlan.{}'.format(sw['vlan_id'])
        if nb.dcim.interfaces.get(device_id=switch.id, name=mgmt_interface_name) is None:
            print('Creating {} for {}'.format(mgmt_interface_name, name))
            mgmt_interface = nb.dcim.interfaces.create(
                device = switch.id,
                name = mgmt_interface_name,
                form_factor = 0,
                description = network_name
            )
            ipv4 = nb.ipam.ip_addresses.create(
                interface = mgmt_interface.id,
                address = "{}/{}".format(str(ipaddress.ip_network(sw['subnet4'])[1]),ipaddress.ip_network(sw['subnet4']).prefixlen),
                status = 1,
                description = network_name
            )
            ipv6 = nb.ipam.ip_addresses.create(
                interface = mgmt_interface.id,
                address = "{}/{}".format(str(ipaddress.ip_network(sw['subnet6'])[1]),ipaddress.ip_network(sw['subnet6']).prefixlen),
                status = 1,
                description = network_name
            )

        ae_interface =  nb.dcim.interfaces.get(device_id=switch.id, name=sw['lag_name'])
        if ae_interface is None:
            print('Creating {} for {}'.format(sw['lag_name'], name))
            ae_interface = nb.dcim.interfaces.create(
                device = switch.id,
                name = sw['lag_name'],
                form_factor = 200,
                description = sw['core_name'],
                mode = 200
            )

        distro_x = int(re.match('s(.*)\.floor', name).group(1))
        core_ae_interface_name = 'ae{}'.format(distro_x + 10)
        core_ae_interface = nb.dcim.interfaces.get(device_id=sw['core_device_id'], name=core_ae_interface_name)
        if core_ae_interface is None:
            print('Creating {} for {}'.format(core_ae_interface_name, sw['core_name']))
            core_ae_interface = nb.dcim.interfaces.create(
                device = sw['core_device_id'],
                name = core_ae_interface_name,
                form_factor = 200,
                description = name
            )

        sw['uplinks'].sort(reverse=True)
        for x, uplink in enumerate(sw['uplinks']):
            uplink = uplink.format(distro_x-1)
            port = sw['local_uplink_ports'][x-1]
            interface = nb.dcim.interfaces.get(device_id=switch.id, name=port)
            if interface.connected_endpoint is None:
                interface.lag = ae_interface.id
                interface.description = '{}:{}'.format(sw['core_name'], uplink)
                interface.save()

                core_interface = nb.dcim.interfaces.get(device_id=sw['core_device_id'], name=uplink)
                core_interface.lag = core_ae_interface.id
                core_interface.description = '{}:{}'.format(name,port)
                core_interface.save()

                print('Creating cable {}:{} -> {}:{}'.format(sw['core_name'], uplink, sw['sysname'], port))
                nb.dcim.cables.create(
                    termination_a_id = core_interface.id,
                    termination_a_type = 'dcim.interface',
                    termination_b_id = interface.id,
                    termination_b_type = 'dcim.interface',
                    status = True,
                    color = 'c0c0c0'
                )

        linknet_vlan = nb.ipam.vlans.get(name='{}-{}-linknet'.format(sw['core_name'], name))
        if linknet_vlan is None:
            linknet_vlan = nb.ipam.vlans.create(
                name='{}-{}-linknet'.format(sw['core_name'], name),
                vid=sw['linknet_vlan_id'],
                status=1,
                site=site_id,
                role=sw['distro_linknet_role']
            )

        print(nb.ipam.prefixes.filter(vlan_id=linknet_vlan.id, family=4, status=1))
        linknet_v4_prefix = nb.ipam.prefixes.get(vlan_id=linknet_vlan.id, family=4, status=1)
        if linknet_v4_prefix is None:
            nb.ipam.prefixes.get(sw['linknet_pool_v4_id']).available_prefixes.create({
                "prefix_length": 31,
                "vlan": linknet_vlan.id,
                "role": 3,
                "description": '{} - {}'.format(sw['core_name'], name)
            })
            linknet_v4_prefix = nb.ipam.prefixes.get(vlan_id=linknet_vlan.id, family=4, status=1)

        linknet_v6_prefix = nb.ipam.prefixes.get(vlan_id=linknet_vlan.id, family=6, status=1)
        if linknet_v6_prefix is None:
            nb.ipam.prefixes.get(sw['linknet_pool_v6_id']).available_prefixes.create({
                "prefix_length": 64,
                "vlan": linknet_vlan.id,
                "role": 3,
                "description": '{} - {}'.format(sw['core_name'], name)
            })
            linknet_v6_prefix = nb.ipam.prefixes.get(vlan_id=linknet_vlan.id, family=6, status=1)

        linknet_interface_name = 'vlan.{}'.format(sw['linknet_vlan_id'])
        if nb.dcim.interfaces.get(device_id=switch.id, name=linknet_interface_name) is None:
            print('Creating {} for {}'.format(linknet_interface_name, name))
            linknet_interface = nb.dcim.interfaces.create(
                device = switch.id,
                name = linknet_interface_name,
                form_factor = 0,
                description = sw['core_name']
            )
            ipv4 = nb.ipam.ip_addresses.create(
                interface = linknet_interface.id,
                address = linknet_v4_prefix.available_ips.list()[1]['address'],
                status = 1,
                description = '{}-{}-linknet'.format(sw['core_name'], name)
            )
            ipv6 = nb.ipam.ip_addresses.create(
                interface = linknet_interface.id,
                address = linknet_v6_prefix.available_ips.list()[1]['address'],
                status = 1,
                description = '{}-{}-linknet'.format(sw['core_name'], name)
            )

        core_linknet_interface_name = '{}.{}'.format(core_ae_interface_name, sw['linknet_vlan_id'])
        if nb.dcim.interfaces.get(device_id=sw['core_device_id'], name=core_linknet_interface_name) is None:
            print('Creating {} for {}'.format(core_linknet_interface_name, sw['core_name']))
            core_linknet_interface = nb.dcim.interfaces.create(
                device = sw['core_device_id'],
                name = core_linknet_interface_name,
                form_factor = 0,
                description = sw['core_name']
            )
            ipv4 = nb.ipam.ip_addresses.create(
                interface = core_linknet_interface.id,
                address = linknet_v4_prefix.available_ips.list()[0]['address'],
                status = 1,
                description = '{}-{}-linknet'.format(sw['core_name'], name)
            )
            ipv6 = nb.ipam.ip_addresses.create(
                interface = core_linknet_interface.id,
                address = linknet_v6_prefix.available_ips.list()[0]['address'],
                status = 1,
                description = '{}-{}-linknet'.format(sw['core_name'], name)
            )

    if sw['is_distro'] is False: # Edge switch that have a distro
        distro_id = nb.dcim.devices.get(name=sw['distro_name']).id
        mgmt_network = nb.ipam.vlans.get(name="mgmt.{}".format(sw['distro_name']))
        ae_interface = nb.dcim.interfaces.get(device_id=switch.id, name=sw['lag_name'])
        if ae_interface is None:
            print('Creating {} for {}'.format(sw['lag_name'], name))
            ae_interface = nb.dcim.interfaces.create(
                device = switch.id,
                name = sw['lag_name'],
                form_factor = 200,
                description = sw['distro_name'],
                mode = 200,
                tagged_vlans = [network.id, mgmt_network.id]
            )
        distro_ae_interface_name = 'ae{}'.format(sw['vlan_id'])
        distro_ae_interface = nb.dcim.interfaces.get(device_id=distro_id, name=distro_ae_interface_name)
        if distro_ae_interface is None:
            print('Creating {} for {}'.format(distro_ae_interface_name,sw['distro_name']))
            distro_ae_interface = nb.dcim.interfaces.create(
                device = distro_id,
                name = distro_ae_interface_name,
                form_factor = 200,
                description = name,
                mode = 200,
                tagged_vlans = [network.id, mgmt_network.id]
            )

        for x, uplink in enumerate(sw['uplinks']):
            port = 'ge-0/0/{}'.format(44+x)
            interface = nb.dcim.interfaces.get(device_id=switch.id, name=port)
            if interface.connected_endpoint is None:
                interface.lag = ae_interface.id
                interface.description = '{}:{}'.format(sw['distro_name'], uplink)
                interface.save()

                distro_interface = nb.dcim.interfaces.get(device_id=distro_id, name=uplink)
                distro_interface.lag = distro_ae_interface.id
                distro_interface.description = '{}:{}'.format(name,port)
                distro_interface.save()

                print('Creating cable {}:{} -> {}:{}'.format(sw['distro_name'], uplink, sw['sysname'], port))
                nb.dcim.cables.create(
                    termination_a_id = distro_interface.id,
                    termination_a_type = 'dcim.interface',
                    termination_b_id = interface.id,
                    termination_b_type = 'dcim.interface',
                    status = True,
                    color = 'c0c0c0'
                )

        vlan_name = 'vlan.{}'.format(DISTRO_MGMT_VLAN_ID)
        vlan_interface = nb.dcim.interfaces.get(device_id=switch.id, name=vlan_name)
        if vlan_interface is None:
            print('Creating {} for {}'.format(vlan_name, name))
            vlan_interface = nb.dcim.interfaces.create(
                device = switch.id,
                name=vlan_name,
                form_factor=0,
                description="mgmt.{}".format(sw['distro_name'])
            )
        if switch.primary_ip4 is None:
            ipv4 = nb.ipam.ip_addresses.get(interface_id=vlan_interface.id, family=4)
            if ipv4 is None:
                ipv4 = nb.ipam.ip_addresses.create(
                    interface=vlan_interface.id,
                    address=sw['mgmt4'],
                    status=1,
                    description="mgmt.{}".format(sw['distro_name'])
                )
            switch.primary_ip4 = ipv4.id
        if switch.primary_ip6 is None:
            ipv6 = nb.ipam.ip_addresses.get(interface_id=vlan_interface.id, family=6)
            if ipv6 is None:
                ipv6 = nb.ipam.ip_addresses.create(
                    interface=vlan_interface.id,
                    address=sw['mgmt6'],
                    status=1,
                    description="mgmt.{}".format(sw['distro_name'])
                )
            switch.primary_ip6 = ipv6.id
        switch.save()

        distro_x = int(re.match('s(.*)\.floor', sw['distro_name']).group(1))
        core_subif_name = 'ae{}.{}'.format(distro_x + 10,sw['vlan_id'])
        core_subif_interface = nb.dcim.interfaces.get(device_id = sw['core_device_id'], name = core_subif_name)
        if core_subif_interface is None:
            print('Creating {} for core {}'.format(core_subif_name, sw['core_name']))
            core_subif_interface = nb.dcim.interfaces.create(
                device = sw['core_device_id'],
                name = core_subif_name,
                form_factor = 0,
                description = "{} - {}:{}".format(network_name, sw['distro_name'], distro_ae_interface.name)
            )
            nb.ipam.ip_addresses.create(
                interface = core_subif_interface.id,
                address = "{}/{}".format(str(ipaddress.ip_network(sw['subnet4'])[1]),ipaddress.ip_network(sw['subnet4']).prefixlen),
                status = 1,
                description = network_name
            )
            nb.ipam.ip_addresses.create(
                interface = core_subif_interface.id,
                address = "{}/{}".format(str(ipaddress.ip_network(sw['subnet6'])[1]),ipaddress.ip_network(sw['subnet6']).prefixlen),
                status = 1,
                description = network_name
            )

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
    if switch[6] not in distros:
        distros[switch[6]] = {
            'sysname': switch[6],
            'subnet4': str(ipaddress.ip_network(switch[3], strict=False)),
            'subnet6': str(ipaddress.ip_network(switch[4], strict=False)),
            'is_distro': True,
            'vlan_role_id': DISTRO_MGMT_VLAN_ROLE,
            'device_type_id': DISTRO_DEVICE_TYPE,
            'device_role_id': DISTRO_DEVICE_ROLE,
            'device_platform_id': DISTRO_DEVICE_PLATFORM,
            'vlan_id': DISTRO_MGMT_VLAN_ID,
            'lag_name': DISTRO_UPLINK_AE,
            'uplinks': CORE_DISTRO_PORTS,
            'local_uplink_ports': DISTRO_UPLINK_PORTS,
            'core_device_id': CORE_DEVICE_ID,
            'core_name': CORE_NAME,
            'linknet_vlan_id': DISTRO_LINKNET_VLAN_ID,
            'loopback_pool_v4_id': LOOPBACK_POOL_V4_ID,
            'loopback_pool_v6_id': LOOPBACK_POOL_V6_ID,
            'linknet_pool_v4_id': LINKNET_POOL_V4_ID,
            'linknet_pool_v6_id': LINKNET_POOL_V6_ID,
            'distro_linknet_role': DISTRO_LINKNET_ROLE
        }

for patch in patchlisttxt:
    patch = patch.strip().split()
    uplink = []
    for p in patch[2:]:
        uplink.append(p)
    switches[patch[0]].update({
        'uplinks': uplink
    })

print('Distro started')
for distro in natsorted(distros):
    sw = distros[distro]
    createswitchandnetwork(sw, FLOOR_SITE)
print('Distro done')
print('Access started')
for switch in natsorted(switches):
    sw = switches[switch]
    createswitchandnetwork(sw, FLOOR_SITE)
print('Access done')

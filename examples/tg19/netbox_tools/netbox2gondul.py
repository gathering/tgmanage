#!/usr/bin/python3

import ipaddress
import requests
import json
from requests.auth import HTTPBasicAuth

import pynetbox

gondul_url = 'https://gondul.tg19.gathering.org'
gondul_user = 'tech'
gondul_pass = '<Removed>'

nb = pynetbox.api(
    'https://netbox.infra.gathering.org',
    token='<Removed>'
)

snmp_community = '<Removed>'

ipam_roles = [1, 2, 5, 4, 7]
#ipam_roles = [1]

switches_roles = [11, 10, 6, 8]
#switches_roles = [11]

# Create vlans/networks
nb_vlans = nb.ipam.vlans.all()
for vlan in nb_vlans:
    if vlan.role is None:
        continue
    if vlan.role.id not in ipam_roles:
        continue
    prefix_v4 = nb.ipam.prefixes.filter(vlan_id=vlan.id, family=4, status=1)
    if len(prefix_v4) <= 0:
        print("No v4 prefix found for vlan {}".format(vlan.name))
        prefix_v4 = None
        gw4 = None
    else:
        prefix_v4 = prefix_v4[0].prefix
        gw4 = ipaddress.IPv4Network(prefix_v4)[1].exploded

    prefix_v6 = nb.ipam.prefixes.filter(vlan_id=vlan.id, family=6, status=1)
    if len(prefix_v6) <= 0:
        print("No v6 prefix found for vlan {}".format(vlan.name))
        prefix_v6 = None
        gw6 = None
    else:
        prefix_v6 = prefix_v6[0].prefix
        gw6 = ipaddress.IPv6Network(prefix_v6)[1].exploded

    router = nb.ipam.ip_addresses.filter(address=gw4)
    if len(router) <= 0:
        print("No router found for vlan {}".format(vlan.name))
        router = None
    else:
        router = router[0].interface.device.name

    #tags = [vlan.role.slug]
    data = json.dumps([{'name': vlan.name, 'subnet4': prefix_v4, 'subnet6': prefix_v6, 'gw4': gw4, 'gw6': gw6, 'router': router, 'vlan': vlan.vid}])
    r = requests.post("{}/api/write/networks".format(gondul_url), data=data, headers={'content-type': 'application/json'}, auth=HTTPBasicAuth(gondul_user, gondul_pass))
    print(r.status_code, r.text, data)

# Create switches/devices
nb_switches = nb.dcim.devices.all()
for switch in nb_switches:
    if switch.device_role is None:
        continue
    if switch.device_role.id not in switches_roles:
        continue
    lag = nb.dcim.interfaces.filter(device_id=switch.id, name='ae0')
    if len(lag) <= 0:
        print("No ae0 found for switch {}, not setting distro".format(switch.name))
        distro = None
        uplink = None
    else:
        uplinks = nb.dcim.interfaces.filter(lag_id=lag[0].id)
        if uplinks is not None and uplinks[0].connected_endpoint is not None:
            distro = uplinks[0].connected_endpoint.device.name
            uplink = "{}.0".format(uplinks[0].connected_endpoint.name)
        else:
            distro = None
            uplink = None

    if switch.primary_ip4 is not None:
        mgmt_vlan = nb.ipam.prefixes.filter(contains=switch.primary_ip4.address, status=1)
        print(mgmt_vlan)
        ip4 = str(switch.primary_ip4.address)
        if len(mgmt_vlan) <= 0:
            print("mgmt_vlan not found for switch {}".format(switch.name))
            mgmt_vlan_name = None
        elif mgmt_vlan[0].vlan is None:
            print("mgmt_vlan not found for switch {}".format(switch.name))
            mgmt_vlan_name = None
        else:
            mgmt_vlan_name = mgmt_vlan[0].vlan.name
    else:
        mgmt_vlan_name = None
        ip4 = ''

    if switch.primary_ip6 is not None:
        ip6 = str(switch.primary_ip6)
    else:
        ip6 = ''

    print(switch.device_role.id)
    if switch.device_role.id != 8:
        traffic_vlan = switch.name
    else:
        traffic_vlan = None

    data = {'sysname': switch.name, 'community': snmp_community}

    if distro is not None:
        data.update({'distro_name': distro})
    if uplink is not None:
        data.update({'distro_phy_port': uplink})
    if traffic_vlan is not None:
        data.update({'traffic_vlan': traffic_vlan})
    if mgmt_vlan_name is not None:
        data.update({'mgmt_vlan': mgmt_vlan_name})
    if ip4 is not None and ip4 != '':
        data.update({'mgmt_v4_addr': ip4})
    if ip6 is not None and ip6 != '':
        data.update({'mgmt_v6_addr': ip6})

    tags = [switch.device_role.slug] + switch.tags
    data.update({'tags': tags})

    data = json.dumps([data])
    print(data)
    r = requests.post("{}/api/write/switches".format(gondul_url), data=data, headers={'content-type': 'application/json'}, auth=HTTPBasicAuth(gondul_user, gondul_pass))
    print(r.status_code, r.reason, data)

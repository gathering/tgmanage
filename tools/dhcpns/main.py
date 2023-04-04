import pynetbox
import os
from dotenv import load_dotenv
import json
from pdns import PowerDNS
import ipaddress
import subprocess
import re
import netaddr

from config.dhcp4 import base as dhcp4
from config.dhcp6 import base as dhcp6
from config.dhcp4 import fap
from config.ddns import base as ddns
from config.ddns import ddns_domain
from config.dhcp4 import subnet as subnet4
from config.dhcp6 import subnet as subnet6


# Take environment variables from .env
load_dotenv()

DOMAIN_NAME = os.environ['DOMAIN_NAME']
DOMAIN_SEARCH = os.environ['DOMAIN_SEARCH']
NAMESERVERS = os.environ['NAMESERVERS'].split()

nb = pynetbox.api(
    os.getenv('NETBOX_URL'),
    token=os.getenv('NETBOX_API_KEY'),
    threading=True,
)

# DNS
pdns = PowerDNS(os.environ['PDNS_API_URL'], os.environ['PDNS_API_KEY'])

# Load all zones to later check if a zone already exist
zones = [zone['name'] for zone in pdns.list_zones()]

rdns_zones = pdns.search("*.arpa", 2000, "zone")

kea4_subnets = []
kea6_subnets = []
kea_ddns_domains = []
kea_rddns_domains = []

# dhcp-client
vlans = nb.ipam.vlans.filter(tag='dhcp-client')
for vlan in vlans:
    vlan_domain_name = f"net-{vlan.name}.{DOMAIN_NAME}"
    prefixes4 = []
    prefixes6 = []
    kea_ddns_domains.append(ddns_domain(vlan_domain_name))

    for prefix in nb.ipam.prefixes.filter(vlan_id=vlan.id, family=4):
        kea4_subnets.append(
            subnet4(vlan, prefix, DOMAIN_NAME, vlan_domain_name))
        prefixes4.append(prefix)

    for prefix in nb.ipam.prefixes.filter(vlan_id=vlan.id, family=6):
        kea6_subnets.append(
            subnet6(vlan, prefix, DOMAIN_NAME, vlan_domain_name))
        prefixes6.append(prefix)

    if f"{vlan_domain_name}." not in zones and len(prefixes4) >= 1:
        print(pdns.create_zone(f"{vlan_domain_name}.", NAMESERVERS))
        print(pdns.create_zone_metadata(
            f"{vlan_domain_name}.", 'TSIG-ALLOW-DNSUPDATE', 'dhcpns'))

        zone_rrsets = []

        for prefix in prefixes4:
            network = ipaddress.ip_network(prefix)

            # Network ID
            zone_rrsets.append({'name': f'id-{network[0]}.{vlan_domain_name}.', 'changetype': 'replace', 'type': 'A', 'records': [
                {'content': str(network[0]), 'disabled': False, 'type':'A'}], 'ttl': 900})

            # Gateway
            zone_rrsets.append({'name': f'gw-{network[1]}.{vlan_domain_name}.', 'changetype': 'replace', 'type': 'A', 'records': [
                {'content': str(network[1]), 'disabled': False, 'type':'A'}], 'ttl': 900})

            # Broadcast
            zone_rrsets.append({'name': f'broadcast-{network[-1]}.{vlan_domain_name}.', 'changetype': 'replace', 'type': 'A', 'records': [
                {'content': str(network[-1]), 'disabled': False, 'type':'A'}], 'ttl': 900})

            # Apply zone_rrsets
            pdns.set_records(vlan_domain_name, zone_rrsets)

            rdns_zone = pdns.get_rdns_zone_from_ip(network[0])
            rdns_rrsets = []
            if rdns_zone is None:
                print(f"Failed to find RDNS Zone for IP {network[0]}")

            # Network ID
            rdns_rrsets.append({"name": network[0].reverse_pointer + '.', "changetype": "replace", "type": "PTR", "records": [
                {"content": f'net-{network[0]}.{vlan_domain_name}.', "disabled": False, "type": "PTR"}], "ttl": 900})

            # Gateway
            rdns_rrsets.append({"name": network[1].reverse_pointer + '.', "changetype": "replace", "type": "PTR", "records": [
                {"content": f'gw-{network[1]}.{vlan_domain_name}.', "disabled": False, "type": "PTR"}], "ttl": 900})

            # Broadcast
            rdns_rrsets.append({"name": network[-1].reverse_pointer + '.', "changetype": "replace", "type": "PTR", "records": [
                {"content": f'broadcast-{network[-1]}.{vlan_domain_name}.', "disabled": False, "type": "PTR"}], "ttl": 900})

            # Apply rdns_rrsets
            pdns.set_records(network[1].reverse_pointer + '.', rdns_rrsets)

# dhcp-mgmt-edge
vlans = nb.ipam.vlans.filter(tag='dhcp-mgmt-edge')
for vlan in vlans:
    prefixes4 = []
    for prefix in nb.ipam.prefixes.filter(vlan_id=vlan.id, family=4):
        kea4_subnets.append(
            fap(vlan, prefix))


for zone in rdns_zones:
    kea_rddns_domains.append(ddns_domain(zone['name'][:-1]))

# Write DDNS
if os.environ['KEA_DDNS_FILE'] is not None:
    with open(os.environ['KEA_DDNS_FILE'], "w") as outfile:
        outfile.write(json.dumps(
            {"DhcpDdns": ddns(kea_ddns_domains, kea_rddns_domains)}, indent=2))

# Write DHCPv4
if os.environ['KEA_DHCP4_FILE'] is not None:
    with open(os.environ['KEA_DHCP4_FILE'], "w") as outfile:
        outfile.write(json.dumps({"Dhcp4": dhcp4(kea4_subnets)}, indent=2))

# Write DHCPv6
if os.environ['KEA_DHCP6_FILE'] is not None:
    with open(os.environ['KEA_DHCP6_FILE'], "w") as outfile:
        outfile.write(json.dumps({"Dhcp6": dhcp6(kea6_subnets)}, indent=2))

# Test DHCPv4
try:
    subprocess.check_call(['/usr/sbin/kea-dhcp4', '-t',
                          os.environ['KEA_DHCP4_FILE']])
except subprocess.CalledProcessError:
    print("Failed to validate kea-dhcp4 config. What do we do now?")

# Test DHCPv6
try:
    subprocess.check_call(['/usr/sbin/kea-dhcp6', '-t',
                          os.environ['KEA_DHCP6_FILE']])
except subprocess.CalledProcessError:
    print("Failed to validate kea-dhcp6 config. What do we do now?")


# Reload all zones
zones = [zone['name'] for zone in pdns.list_zones()]

# Create DNS for devices
devices = nb.dcim.devices.all()
for device in devices:
    if device.primary_ip4 is None or device.primary_ip6 is None:
        continue

    zone = "tg23.gathering.org"

    # IPv4
    zone_rrsets = []
    if device.primary_ip4 is not None:
        zone_rrsets.append({'name': f'{device.name}.{zone}.', 'changetype': 'replace', 'type': 'A', 'records': [
            {'content': str(netaddr.IPNetwork(str(device.primary_ip4)).ip), 'disabled': False, 'type': 'A'}], 'ttl': 900})

    # IPv6    
    if device.primary_ip6 is not None:
        zone_rrsets.append({'name': f'{device.name}.{zone}.', 'changetype': 'replace', 'type': 'AAAA', 'records': [
            {'content': str(netaddr.IPNetwork(str(device.primary_ip6)).ip), 'disabled': False, 'type': 'A'}], 'ttl': 900})

    if len(zone_rrsets) > 1:
        # Apply zone_rrsets
        print(pdns.set_records(zone, zone_rrsets))

        rdns_zone = pdns.get_rdns_zone_from_ip(
            str(netaddr.IPNetwork(str(device.primary_ip4)).ip))
        rdns_rrsets = []
        if rdns_zone is None:
            print(f"Failed to find RDNS Zone for IP")

    # IPv4 RDNS
    rdns_rrsets.append({"name": ipaddress.ip_address(str(netaddr.IPNetwork(str(device.primary_ip4)).ip)).reverse_pointer + '.', "changetype": "replace", "type": "PTR", "records": [
        {"content": f'{device.name}.{zone}.', "disabled": False, "type": "PTR"}], "ttl": 900})

    # Apply rdns_rrsets
    print(pdns.set_records(rdns_zone, rdns_rrsets))

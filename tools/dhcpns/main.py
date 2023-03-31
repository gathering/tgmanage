import pynetbox
import os
from dotenv import load_dotenv
import json
from pdns import PowerDNS

from config.dhcp4 import base as dhcp4
from config.dhcp6 import base as dhcp6
from config.ddns import base as ddns
from config.ddns import ddns_domain
from config.dhcp4 import subnet as subnet4
from config.dhcp6 import subnet as subnet6

import ipaddress

# Take environment variables from .env
load_dotenv()

DOMAIN_NAME = os.environ['DOMAIN_NAME']
DOMAIN_SEARCH = os.environ['DOMAIN_SEARCH']
NAMESERVERS = os.environ['NAMESERVERS'].strip().split(',')

nb = pynetbox.api(
    os.getenv('NETBOX_URL'),
    token=os.getenv('NETBOX_API_KEY'),
    threading=True,
)

# DNS
pdns = PowerDNS(os.environ['PDNS_API_URL'], os.environ['PDNS_API_KEY'])

# Load all zones to later check if a zone already exist
zones = [ zone['name'] for zone in pdns.list_zones() ]

rdns_zones = pdns.search("*.arpa", 2000, "zone")

kea4_subnets = []
kea6_subnets = []
kea_ddns_domains = []
kea_rddns_domains = []

vlans = nb.ipam.vlans.filter(tag='dhcp')
for vlan in vlans:
    vlan_domain_name = f"{vlan.name}.{DOMAIN_NAME}"
    prefixes4 = []
    prefixes6 = []
    kea_ddns_domains.append(ddns_domain(vlan_domain_name))

    for prefix in nb.ipam.prefixes.filter(vlan_id=vlan.id, family=4):
        kea4_subnets.append(
            subnet4(vlan, prefix, DOMAIN_NAME, vlan_domain_name))
        #prefixes4.append(prefix)

    for prefix in nb.ipam.prefixes.filter(vlan_id=vlan.id, family=6):
        kea6_subnets.append(
            subnet6(vlan, prefix, DOMAIN_NAME, vlan_domain_name))
        #prefixes6.append(prefix)

    if vlan_domain_name not in zones and len(prefixes4) >= 1:
        pdns.create_zone(vlan_domain_name, NAMESERVERS)
        pdns.create_zone_metadata(
            vlan_domain_name, 'TSIG-ALLOW-DNSUPDATE', 'dhcp_updater')

        zone_rrsets = []

        for prefix in prefixes4:
            network = ipaddress.ip_network(prefix)

            # Network ID
            zone_rrsets.append({'name': f'net-{network[0]}.{vlan_domain_name}', 'changetype': 'replace', 'type': 'A', 'records': [
                {'content': str(network[0]), 'disabled': False, 'type':'A'}], 'ttl': 900})

            # Gateway
            zone_rrsets.append({'name': f'gw-{network[1]}.{vlan_domain_name}', 'changetype': 'replace', 'type': 'A', 'records': [
                {'content': str(network[1]), 'disabled': False, 'type':'A'}], 'ttl': 900})

            # Broadcast
            zone_rrsets.append({'name': f'broadcast-{network[-1]}.{vlan_domain_name}', 'changetype': 'replace', 'type': 'A', 'records': [
                {'content': str(network[-1]), 'disabled': False, 'type':'A'}], 'ttl': 900})

            rdns_zone = pdns.get_rdns_zone_from_ip(network[0])
            rdns_rrsets = []
            if rdns_zone is None:
                print(f"Failed to find RDNS Zone for IP {network[0]}")

            # Network ID
            rdns_rrsets.append({"name": network[0].reverse_pointer + '.', "changetype": "replace", "type": "PTR", "records": [
                {"content": f'net-{network[0]}.{vlan_domain_name}', "disabled": False, "type": "PTR"}], "ttl": 900})

            # Gateway
            rdns_rrsets.append({"name": network[1].reverse_pointer + '.', "changetype": "replace", "type": "PTR", "records": [
                {"content": f'gw-{network[1]}.{vlan_domain_name}', "disabled": False, "type": "PTR"}], "ttl": 900})

            # Broadcast
            rdns_rrsets.append({"name": network[-1].reverse_pointer + '.', "changetype": "replace", "type": "PTR", "records": [
                {"content": f'broadcast-{network[-1]}.{vlan_domain_name}', "disabled": False, "type": "PTR"}], "ttl": 900})


for zone in rdns_zones:
    kea_rddns_domains.append(ddns_domain(zone['name'][:-1]))

# Write DDNS
if os.environ['KEA_DDNS_FILE'] is not None:
    with open(os.environ['KEA_DDNS_FILE'], "w") as outfile:
        outfile.write(json.dumps({"DhcpDdns": ddns(kea_ddns_domains, kea_rddns_domains)}, indent=2))

# Write DHCPv4
if os.environ['KEA_DHCP4_FILE'] is not None:
    with open(os.environ['KEA_DHCP4_FILE'], "w") as outfile:
        outfile.write(json.dumps({"Dhcp4": dhcp4(kea4_subnets)}, indent=2))
        
# Write DHCPv4
if os.environ['KEA_DHCP6_FILE'] is not None:
    with open(os.environ['KEA_DHCP6_FILE'], "w") as outfile:
        outfile.write(json.dumps({"Dhcp6": dhcp4(kea6_subnets)}, indent=2))

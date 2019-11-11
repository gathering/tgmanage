#!/usr/bin/python3

import argparse
import ipaddress
import re
import json

from pdns import PowerDNS

def main():
    parser = argparse.ArgumentParser(description='Make reverse zones')
    parser.add_argument('--key', help='PowerDNS Web API key', required=True)
    parser.add_argument('--host', help='PowerDNS Web API url. Default: http://127.0.0.1:8081/api/v1', default='http://127.0.0.1:8081/api/v1')
    parser.add_argument('nets', nargs='*', help="Example: ./make_reverse_zones.py --key PDNSAPIKEY 2a06:5840::/29 185.110.148.0/22 88.92.0.0/17")
    args = parser.parse_args()

    nameservers = ['ns1.infra.gathering.org.', 'ns2.infra.gathering.org.']

    # Connect to powerdns api
    pdns = PowerDNS(args.host,args.key)

    if len(args.nets) < 1:
        print("Argument with block is required. Example: ./make_reverse_zones.py 2a06:5840::/29 185.110.148.0/22 88.92.0.0/17")
        exit(1)

    # Load all zones to later check if a zone already exist.
    zones = []
    pdns_zones = pdns.list_zones()
    for zone in pdns_zones:
        zones.append(zone['name'])

    # Loop all nets in args
    for net in args.nets:
        block = ipaddress.ip_network(net)

        # IPv4 - Split the network up in /24 blocks
        if block.version == 4 and block.prefixlen <= 24:
            blocks = list(block.subnets(new_prefix=24))
            for bl in blocks:
                net_id = ipaddress.ip_network(bl).network_address
                p = re.compile('(.*)\.(.*)\.(.*)\.(.*)')
                m = p.match(str(net_id))
                ip4_arpa = '{}.{}.{}.in-addr.arpa.'.format(m.group(3),m.group(2),m.group(1))
                if ip4_arpa not in zones:
                    print("Creating zone {}".format(ip4_arpa))
                    pdns.create_zone(ip4_arpa, nameservers)
                else:
                    print(pdns.get_zone_metadata(ip4_arpa))
                    pdns.create_zone_metadata(ip4_arpa, 'TSIG-ALLOW-DNSUPDATE', 'dhcpdupdate')
                    #print("{} already exists, skipping.".format(ip4_arpa))

        elif block.version == 4:
            print("{} can't be smaller then /24 (bigger number)".format(net))
            exit(1)

        # IPv6 - Split the network up in /32 blocks
        if block.version == 6 and block.prefixlen <= 32:
            blocks = list(block.subnets(new_prefix=32))
            for bl in blocks:
                reverse = ipaddress.ip_network((bl)[0]).reverse_pointer
                # Hardcoded to /32, will need to be modified if we need smaller nets then /32 (bigger number)
                p = re.compile('8\.2\.1\.\/\.(0\.0\.0\.0\.0\.0\.0\.0\.0\.0\.0\.0\.0\.0\.0\.0\.0\.0\.0\.0\.0\.0\.0\.0\.)(.*ip6.arpa)$')
                m = p.match(str(reverse))
                ip6_arpa = '{}.'.format(m.group(2))
                if ip6_arpa not in zones:
                    print("Creating zone {}".format(ip6_arpa))
                    pdns.create_zone(ip6_arpa, nameservers)
                else:
                    print(pdns.get_zone_metadata(ip6_arpa))
                    pdns.create_zone_metadata(ip6_arpa, 'TSIG-ALLOW-DNSUPDATE', 'dhcpdupdate')
        elif block.version == 6:
            print("{} can't be smaller then /32 (bigger number)".format(net))
            exit(1)

if __name__ == "__main__":
    main()

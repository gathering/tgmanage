import os
import ipaddress


def base(subnet6):
    return {
        "hooks-libraries": [
        ],
        "interfaces-config": {
            "interfaces": [
                "{}/{}".format(os.environ.get('DHCP_INTERFACE', 'eth0'), os.environ.get('DHCP_INTERFACE_V6'))
            ]       
        },
        "control-socket": {
            "socket-type": "unix",
            "socket-name": "/tmp/kea6-ctrl-socket"
        },
        "lease-database": {
            "type": "postgresql",
            "name": "kea",
            "user": "kea",
            "password": os.environ['DHCP_LEASE_DB_PASSWORD']
        },
        "expired-leases-processing": {
            "reclaim-timer-wait-time": 10,
            "flush-reclaimed-timer-wait-time": 25,
            "hold-reclaimed-time": 3600,
            "max-reclaim-leases": 100,
            "max-reclaim-time": 250,
            "unwarned-reclaim-cycles": 5
        },
        "renew-timer": 900,
        "rebind-timer": 1800,
        "preferred-lifetime": 3000,
        "valid-lifetime": 3600,
        "option-data": [
            {
                "name": "dns-servers",
                "data": os.environ['DOMAIN_NAME_SERVERS_V6']
            },
            {
                "name": "domain-search",
                "data": os.environ['DOMAIN_SEARCH']
            },
            {
            "name": "unicast",
            "data": os.environ.get('DHCP_INTERFACE_V6')
            }
        ],
        "subnet6": subnet6
    }


def subnet(vlan, prefix, domain_name, vlan_domain_name):
    network = ipaddress.ip_network(prefix.prefix)
    return {
            "id": prefix.id,
            "subnet": prefix.prefix,
            "ddns-qualifying-suffix": vlan_domain_name,
            "pools": [
                {
                    "pool": f"{network[0]}10-{network[0]}ffff"
                }
            ],
            "option-data": [
                {
                    "name": "domain-search",
                    "data": f"{vlan_domain_name}, {domain_name}"
                }
            ],
            "user-context": {
                "name": vlan.name,
                "type": "clients"
            }
        }
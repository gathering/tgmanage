import os
import ipaddress

from .base import POSTGRESQL_HOOK, LEASE_API_HOOK, SUBNET_CMDS_HOOK

def base(subnet6):
    return {
        "loggers": [
            {
                "name": "kea-dhcp6",
                "severity": "INFO",
                "output_options": [
                    {
                        "output": "/var/log/kea/kea-dhcp66.log",
                        "pattern": "%-5p %m\n"
                    }
                ]
            }
        ],
        "hooks-libraries": [
            POSTGRESQL_HOOK,
            LEASE_API_HOOK,
            SUBNET_CMDS_HOOK,
        ],
        "interfaces-config": {
            "interfaces": [
                "{}/{}".format(os.environ.get('DHCP_INTERFACE',
                               'eth0'), os.environ.get('DHCP_INTERFACE_V6'))
            ]
        },
        "control-sockets":[ 
            {
                "socket-type": "unix",
                "socket-name": "/var/run/kea/dhcp6"
            },
            {
                "socket-type": "http",
                "socket-address": "0.0.0.0",
                "socket-port": 8086
            }
        ],

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
        "valid-lifetime": 3600, # TODO 4 timer
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
        "subnet6": subnet6,
        "loggers": [
            {
                "name": "kea-dhcp6",
                "output_options": [
                    {
                        "output": "/var/log/kea/dhcp6-debug.log",
                        "maxver": 8,
                        "maxsize": 204800,
                        "flush": True,
                        "pattern": "%d{%j %H:%M:%S.%q} %c %m\n"
                    }
                ],
                "severity": "DEBUG",
                "debuglevel": 40
            }
        ]
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
            "vlan-id": vlan.id,
            "type": "clients"
        }
    }

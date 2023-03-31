import os
import ipaddress


def base(subnet4):
    return {
        "hooks-libraries": [
            {
                "library": "/usr/lib/x86_64-linux-gnu/kea/hooks/libdhcp_flex_option.so",
                "parameters": {
                    "options": [
                        {
                            "name": "vendor-encapsulated-options",
                            "client-class": "fap-class",
                            "sub-options": [
                                    {
                                        "name": "config-file-name",
                                        "space": "vendor-encapsulated-options-space",
                                        "supersede": "ifelse(option[82].option[1].exists,concat('api/templates/magic.conf/a=', option[82].option[1].hex),'')"
                                    }
                            ]
                        },
                        {
                            "name": "host-name",
                            "client-class": "fap-class",
                            "remove": "option[12].exists"
                        }
                    ]
                }
            },
            {
                "library": "/usr/lib/x86_64-linux-gnu/kea/hooks/libdhcp_run_script.so",
                "parameters": {
                    "name": "/etc/kea/gondul.sh",
                    "sync": False
                }
            }
        ],
        "interfaces-config": {
            "interfaces": [
                os.environ.get('DHCP_INTERFACE', 'eth0')
            ],
            "dhcp-socket-type": "udp"
        },
        "control-socket": {
            "socket-type": "unix",
            "socket-name": "/tmp/kea4-ctrl-socket"
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
        "authoritative": True,
        "renew-timer": 900,
        "rebind-timer": 1800,
        "valid-lifetime": 3600,
        "option-def": [
            {
                "name": "image-file-name",
                "code": 0,
                "space": "vendor-encapsulated-options-space",
                "type": "string",
                "array": False
            },
            {
                "name": "config-file-name",
                "code": 1,
                "space": "vendor-encapsulated-options-space",
                "type": "string",
                "array": False
            },
            {
                "name": "image-file-type",
                "code": 2,
                "space": "vendor-encapsulated-options-space",
                "type": "string",
                "array": False
            },
            {
                "name": "transfer-mode",
                "code": 3,
                "space": "vendor-encapsulated-options-space",
                "type": "string",
                "array": False
            },
            {
                "code": 150,
                "name": "tftp-server-address",
                "space": "dhcp4",
                "type": "ipv4-address",
                "array": True
            }
        ],
        "option-data": [
            {
                "name": "domain-name-servers",
                "data": os.environ['DOMAIN_NAME_SERVERS_V4']
            },
            {
                "name": "domain-name",
                "data": os.environ['DOMAIN_NAME']
            },
            {
                "name": "domain-search",
                "data": os.environ['DOMAIN_SEARCH']
            }
        ],
        "client-classes": [
            {
                "name": "client-juniper-vendor",
                "test": "substring(option[vendor-class-identifier].hex,0,10) == 'Juniper-ex'"
            },
            {
                "name": "client-juniper-mac",
                "test": "substring(pkt4.mac, 0, 2) == '0x44f477' or substring(pkt4.mac, 0, 2) == '0xf01c2d'"
            },
            {
                "name": "fap-class",
                "test": "member('client-juniper-vendor') or member('client-juniper-mac')",
                "option-data": [
                    {
                        "name": "vendor-encapsulated-options",
                        "always-send": True
                    },
                    {
                        "name": "transfer-mode",
                        "space": "vendor-encapsulated-options-space",
                        "data": "http",
                        "always-send": True
                    },
                    {
                        "name": "tftp-server-address",
                        "data": os.environ['FAP_V4'],
                        "always-send": True
                    }
                ]
            },
            {
                "name": "Cisco-Phone",
                "test": "substring(option[60].hex,0,28) == 'Cisco Systems, Inc. IP Phone'",
                "option-data": [
                    {
                        "name": "tftp-server-address",
                        "data": os.environ['VOIP_V4'],
                        "always-send": True
                    },
                ],
            },
            {
                "name": "PXE-XClient_iPXE",
                "test": "substring(option[77].hex,0,4) == 'iPXE'",
                "boot-file-name": "https://{}/menu.ipxe".format(os.environ['NETBOOT_V4'])
            },
            {
                "name": "PXE-UEFI-32-1",
                "test": "substring(option[60].hex,0,20) == 'PXEClient:Arch:00006'",
                "next-server": os.environ['NETBOOT_V4'],
                "boot-file-name": "netboot.xyz.efi"
            },
            {
                "name": "PXE-UEFI-32-2",
                "test": "substring(option[60].hex,0,20) == 'PXEClient:Arch:00002'",
                "next-server": os.environ['NETBOOT_V4'],
                "boot-file-name": "netboot.xyz.efi"
            },
            {
                "name": "PXE-UEFI-64-1",
                "test": "substring(option[60].hex,0,20) == 'PXEClient:Arch:00007'",
                "next-server": os.environ['NETBOOT_V4'],
                "boot-file-name": "netboot.xyz.efi"
            },
            {
                "name": "PXE-UEFI-64-2",
                "test": "substring(option[60].hex,0,20) == 'PXEClient:Arch:00008'",
                "next-server": os.environ['NETBOOT_V4'],
                "boot-file-name": "netboot.xyz.efi"
            },
            {
                "name": "PXE-UEFI-64-3",
                "test": "substring(option[60].hex,0,20) == 'PXEClient:Arch:00009'",
                "next-server": os.environ['NETBOOT_V4'],
                "boot-file-name": "netboot.xyz.efi"
            },
            {
                "name": "PXE-Legacy",
                "test": "substring(option[60].hex,0,20) == 'PXEClient:Arch:00000'",
                "next-server": os.environ['NETBOOT_V4'],
                "boot-file-name": "netboot.xyz-undionly.kpxe"
            }
        ],
        "subnet4": subnet4
    }


def subnet(vlan, prefix, domain_name, vlan_domain_name):
    network = ipaddress.ip_network(prefix.prefix)
    gw, start_ip, end_ip = network[1], network[2], network[-2]
    return {
        "id": prefix.id,
        "subnet": prefix.prefix,
        "ddns-qualifying-suffix": vlan_domain_name,
        "pools": [
            {
                "pool": f"{start_ip} - {end_ip}"
            }
        ],
        "option-data": [
            {
                "name": "routers",
                "data": f"{gw}"
            },
            {
                "name": "domain-name",
                "data": f"{vlan_domain_name}, {domain_name}"
            },
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


def fap(vlan, prefix, domain_name, vlan_domain_name):
    network = ipaddress.ip_network(prefix.prefix)
    gw, start_ip, end_ip = network[1], network[len(network) / 2], network[-2]
    return {
        "id": prefix.id,
        "client-class": "fap-class",
        "subnet": prefix.prefix,
        "pools": [
            {
                "pool": f"{start_ip} - {end_ip}"
            }
        ],
        "option-data": [
            {
                "name": "routers",
                "data": f"{gw}"
            },
            {
                "name": "domain-name",
                "data": f"{vlan_domain_name}, {domain_name}"
            },
            {
                "name": "domain-search",
                "data": f"{vlan_domain_name}, {domain_name}"
            }
        ],
        "user-context": {
            "name": vlan.name,
            "type": "fap"
        }
    }

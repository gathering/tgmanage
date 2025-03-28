import os

def base(ddns_domains = [], ddns_reverse_domains = []):
    return {
        "ip-address": "::1",
        "port": 53001,
        "control-socket": {
            "socket-type": "unix",
            "socket-name": "/tmp/kea-ddns-ctrl-socket"
        },
        "tsig-keys": [
            {
                "name": os.environ['KEA_DDNS_KEY_NAME'],
                "algorithm": os.environ['KEA_DDNS_ALGORITHM'],
                "secret": os.environ['KEA_DDNS_SECRET']
            }
        ],
        "forward-ddns": {
            "ddns-domains": ddns_domains
        },
        "reverse-ddns": {
            "ddns-domains": ddns_reverse_domains
        },
        "loggers": [
            {
                "name": "kea-dhcp-ddns",
                "output_options": [
                    {
                        "output": "/var/log/kea/ddns-debug.log",
                        "maxver": 8,
                        "maxsize": 204800,
                        "flush": True,
                        "pattern": "%d{%j %H:%M:%S.%q} %c %m\n"
                    }
                ],
                "severity": "INFO",
                "debuglevel": 0
            }
        ]
    }


def ddns_domain(domain_name):
    return {
            "name": f"{domain_name}.",
            "key-name": os.environ['KEA_DDNS_KEY_NAME'],
            "dns-servers": [
                    {
                        "ip-address": "::1",
                        "port": 53
                    }
            ]
        }
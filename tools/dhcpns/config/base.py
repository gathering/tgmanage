import os

POSTGRESQL_HOOK = {
    "library": "/usr/lib/x86_64-linux-gnu/kea/hooks/libdhcp_pgsql.so",
    "parameters": {},
}

LEASE_DATABASE = {
    "type": "postgresql",
    "name": "kea",
    "user": "kea",
    "password": os.environ['DHCP_LEASE_DB_PASSWORD']
}

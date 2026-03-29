from datetime import timedelta


POSTGRESQL_HOOK = {
    "library": "/usr/lib/x86_64-linux-gnu/kea/hooks/libdhcp_pgsql.so",
    "parameters": {},
}
LEASE_API_HOOK =  {
    "library": "/usr/lib/x86_64-linux-gnu/kea/hooks/libdhcp_lease_cmds.so",
    "parameters": {}
}
SUBNET_CMDS_HOOK = {
    "library": "/usr/lib/x86_64-linux-gnu/kea/hooks/libdhcp_subnet_cmds.so",
    "parameters": {}
}

FAP_VALID_LIFETIME = timedelta(minutes=15)
FAP_LEASE = {
    "rebind-timer": FAP_VALID_LIFETIME.seconds * 0.875,
    "renew-timer": FAP_VALID_LIFETIME.seconds * 0.5,
    "valid-lifetime": FAP_VALID_LIFETIME.seconds,
}

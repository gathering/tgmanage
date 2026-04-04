# Configuration from TG26

A few scripts in [../../tools/](../../tools/) were also used,
namely ztprince (ZTP server) and dhcpns for dhcp and authorative dns configuration.

We also used this script to generate all floor switches,
based on the output from [../../planning](../../planning).

```fish
for line in (bat patchlist.txt); set name (echo $line | awk '{print $1}'); set upstream (echo $line | awk '{print $2}'); set links (echo $line | awk '{print $3 "," $4 "," $5}'); curl -v -H "Authorization: Token $NETBOX_TOKEN" -H "content-type: application/json" https://netbox.tg26.tg.no/api/extras/scripts/create-switch.CreateSwitch/ --data '{"data": {"switch_name": "'$name'", "device_type": "EX2200-48T-4G", "device_role": "Access switch", "uplink_type": "", "destination_device_a": "'$upstream'", "destination_device_b": "", "destination_interfaces": "'$links'", "trigger_awx_playbook": false}, "commit": true}'; end
```

Netbox was also used, via the [https://github.com/gathering/tg-netbox](tg-netbox repo).

AVD/CVP was configured via the private repo [https://github.com/gathering/tg25-arista-avd](arista-avd),
based on Arista's example: [https://github.com/aristanetworks/avd](https://github.com/aristanetworks/avd).

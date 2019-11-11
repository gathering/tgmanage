import pynetbox
from pdns import PowerDNS
import configparser
import netaddr

config = configparser.ConfigParser()
config.read('config.ini')

nb = pynetbox.api(config['EVENT']['netbox_url'], token=config['EVENT']['netbox_api_key'])
pdns = PowerDNS(config['DNS']['api_url'], config['DNS']['api_key'])

#devices = nb.dcim.devices.all()
#for device in devices:
#    if device.site.name == 'Floor':
#        continue
#    pdns.create_netbox_device_record(device, config['EVENT']['domain'], config['EVENT']['lol_domain'])

vms = nb.virtualization.virtual_machines.all()
for vm in vms:
    pdns.create_netbox_device_record(vm, config['EVENT']['domain'], config['EVENT']['lol_domain'])

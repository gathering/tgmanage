import json
import requests

from django.contrib.contenttypes.models import ContentType

from dcim.choices import InterfaceModeChoices, InterfaceTypeChoices
from dcim.models import Cable, CableTermination, Device, DeviceRole, DeviceType, Interface, Site
from ipaddress import IPv6Address
from extras.models import Tag
from extras.scripts import *
from ipam.models import IPAddress, Prefix, VLAN, VLANGroup
from netaddr import IPNetwork


CONFIG_FILE = '/etc/netbox/scripts/mist.json'

# Used for getting existing types/objects from Netbox.
AP_DEVICE_ROLE = DeviceRole.objects.get(name='AP')
DEFAULT_SITE = Site.objects.get(slug='hele-skpet')
WIFI_MGMT_VLAN = VLAN.objects.get(name="wifi-mgmt.floor.r1.tele")
WIFI_TRAFFIC_VLAN = VLAN.objects.get(name="wifi-lol")
CORE_DEVICE = Device.objects.get(name="r1.tele")

TG = Tag.objects.get
WIFI_TAGS = [TG(slug="deltagere")]

# TODO: "distro" needs various tags, auto-add ? or warn in gondul?

def fetch_from_mist():
    site = None
    token = None
    with open(CONFIG_FILE, 'r') as f:
        contents = f.read()
        j = json.loads(contents)
        site = j['site']
        token = j['token']

    site_url = f"https://api.eu.mist.com/api/v1/sites/{site}/stats/devices"
    resp = requests.get(site_url,
        None,
        headers={
           'authorization': f'Token {token}',
        },
    )
    return resp.json()

def create_device_from_mist(data):
    model = DeviceType.objects.get(model=data['model'])
    device, _created = Device.objects.get_or_create(
        name=data['name'],
        device_role=AP_DEVICE_ROLE,
        device_type=model,
        site=DEFAULT_SITE,
    )

    return device

def get_distro_from_mist(data):
    if 'lldp_stat' not in data:
        return None, None
    distro_name = data['lldp_stat']['system_name']
    distro_name = distro_name.replace(".tg23.gathering.org", "")
    try:
        distro = Device.objects.get(name=distro_name)
        distro_port = distro.interfaces.get(name=data['lldp_stat']['port_id'])
        return distro, distro_port
    except Device.DoesNotExist:
        return None, None

class Mist2Netbox(Script):

    class Meta:
        name = "Mist to netbox"
        description = "Import devices from Mist to Netbox"
        commit_default = False
        field_order = ['site_name', 'switch_count', 'switch_model']
        fieldsets = ""

    def run(self, data, commit):

        devices = fetch_from_mist()

        import_tag, _created = Tag.objects.get_or_create(name="from-mist")

        self.log_info(f"Importing {len(devices)} switches")
        for device_data in devices:
            self.log_debug(f"Managing device from {device_data}")

            device = create_device_from_mist(device_data)
            
            self.log_debug(f"Managing {device}")

            distro, distro_port = get_distro_from_mist(device_data)
            if not distro and not distro_port:
                self.log_warning(f"Skipping {device}, missing distro information")
                device.delete()
                continue


            mgmt_vlan = WIFI_MGMT_VLAN

            interface = None
            interface, _created_interface = Interface.objects.get_or_create(
                device=device,
                name="eth0",
            )
            interface.description = distro.name
            interface.mode = InterfaceModeChoices.MODE_TAGGED
            interface.save()
            interface.tagged_vlans.add(mgmt_vlan)
            
            # distro side
            distro_interface, _created_distro_interface = Interface.objects.get_or_create(
                device=distro,
                name=distro_port,
            )
            distro_interface.description = device.name
            distro_interface.mode = InterfaceModeChoices.MODE_TAGGED
            distro_interface.save()
            distro_interface.tagged_vlans.add(mgmt_vlan)

            interface.tagged_vlans.add(WIFI_TRAFFIC_VLAN)


            # Cabling
            interface_type = ContentType.objects.get_for_model(Interface)
            # Delete A cable termination if it exists
            try:
                CableTermination.objects.get(
                    cable_end='A',
                    termination_id=distro_interface.id,
                    termination_type=interface_type,
                ).delete()
            except CableTermination.DoesNotExist:
                pass

            # Delete B cable termination if it exists
            try:
                CableTermination.objects.get(
                    cable_end='B',
                    termination_id=interface.id,
                    termination_type=interface_type,
                ).delete()
            except CableTermination.DoesNotExist:
                pass
            
            # Create cable now that we've cleaned up the cable mess.
            cable = Cable.objects.create()
            a = CableTermination.objects.create(
                cable=cable,
                cable_end='A',
                termination_id=distro_interface.id,
                termination_type=interface_type,
            )
            b = CableTermination.objects.create(
                cable_end='B',
                cable=cable,
                termination_id=interface.id,
                termination_type=interface_type,
            )

            cable = Cable.objects.get(id=cable.id)
            # https://github.com/netbox-community/netbox/discussions/10199
            cable._terminations_modified = True
            cable.save()
            cable.tags.add(import_tag)

            # Set mgmt ip
            mgmt_addr_ipv4 = device_data['ip_stat']['ip']
            mgmt_addr_ipv4_netmask = device_data['ip_stat']['netmask']
            mgmt_addr_v4 = f"{mgmt_addr_ipv4}/25"  # netmask is in cidr notation, and netmask6 is in prefix notation. why?
            if device.primary_ip4 and device.primary_ip4 != mgmt_addr_v4:
                device.primary_ip4.delete()
            mgmt_addr_v4, _ = IPAddress.objects.get_or_create(
                address=mgmt_addr_v4,
                assigned_object_type=interface_type,
                assigned_object_id=interface.id,
            )
            mgmt_addr_ipv6 = device_data['ip_stat']['ip6']
            mgmt_addr_ipv6_netmask = device_data['ip_stat']['netmask6']
            mgmt_addr_v6 = f"{mgmt_addr_ipv6}{mgmt_addr_ipv6_netmask}"
            if device.primary_ip6 and device.primary_ip6 != mgmt_addr_v6:
                device.primary_ip6.delete()
            if IPv6Address(str(mgmt_addr_ipv6)).is_global:
                self.log_warning(f"AP {device.name} missing global IPv6 address")
                mgmt_addr_v6, _ = IPAddress.objects.get_or_create(
                    address=mgmt_addr_v6,
                    assigned_object_type=interface_type,
                    assigned_object_id=interface.id,
                )
            else:
                mgmt_addr_v6 = None
            device = Device.objects.get(pk=device.pk)
            device.primary_ip4 = mgmt_addr_v4
            device.primary_ip6 = mgmt_addr_v6
            device.save()

            if "locating" in device_data:
                locating_tag, _ = Tag.objects.get_or_create(name="locating")
                if device_data["locating"]:
                    device.tags.add(locating_tag)
                else:
                    device.tags.remove(locating_tag)

            # Add tag to everything we created so it's easy to identify in case we
            # want to recreate
            things_we_created = [
                device,
                mgmt_addr_v4,
                mgmt_addr_v6,
            ]
            for thing in things_we_created:
                if not thing:
                    continue
                thing.tags.add(import_tag)

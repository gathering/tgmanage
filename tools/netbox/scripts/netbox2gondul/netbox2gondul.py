from django.contrib.contenttypes.models import ContentType
from django.db.models import F
from django.utils.text import slugify

from dcim.choices import DeviceStatusChoices, InterfaceModeChoices, InterfaceTypeChoices, SiteStatusChoices
from dcim.models import Cable, CableTermination, Device, DeviceRole, DeviceType, Interface, Manufacturer, Site
from extras.scripts import *
from ipam.models import IPAddress, Prefix, VLAN
from ipam.lookups import NetContainsOrEquals

import ipaddress
import json
import re
import requests
from requests.models import HTTPBasicAuth

GONDUL_URL = ""
GONDUL_USERNAME = ""
GONDUL_PASSWORD = ""

def find_prefix_for_device(device) -> Prefix:
    pass


class Netbox2Gondul(Script):

    class Meta:
        name = "Sync NetBox to Gondul"
        description = re.sub(r'^\s*', '', """
            Can be done for a single network/device or a full sync. Note that this will not do 'renames' of devices, so it is best used for updating device information.
            If a device is selected, it will also sync the required networks as long as they are set up correctly (Primary IP addresses for the Device & VLAN configured for the Prefix of those IP Addresses).
        """)

    device = ObjectVar(
        description="Device",
        model=Device,
        required=True,
    )
    """
    vlan = ObjectVar(
        description="VLAN",
        model=VLAN,
        required=False,
    )
    prefix_v4 = ObjectVar(
        description="IPv4 Prefix",
        model=Prefix,
        query_params={
            'family': 4,
            'vlan_id': '$vlan'
        },
        required=False,
    )
    prefix_v6 = ObjectVar(
        description="IPv6 Prefix",
        model=Prefix,
        query_params={
            'family': 6,
            'vlan_id': '$vlan'
        },
        required=False,
    )
    """

    def network_to_gondul(self, vlan: VLAN, prefix_v4: Prefix, prefix_v6: Prefix):
        self.log_info(f"Posting {vlan.name} to Gondul")

        gondul_auth = HTTPBasicAuth(GONDUL_USERNAME, GONDUL_PASSWORD)
    
        subnet4 = None
        subnet6 = None
        gw4 = None
        gw6 = None
        router = None

        if prefix_v4:
            subnet4 = str(prefix_v4.prefix)
            gw4 = str(ipaddress.IPv4Network(prefix_v4.prefix)[1])
        else:
            self.log_warning(f'Network for VLAN <a href="{vlan.get_absolute_url()}">{vlan.name}</a> is missing IPv4 Prefix')

        if prefix_v6:
            subnet6 = str(prefix_v6.prefix)
            gw6 = str(ipaddress.IPv6Network(prefix_v6.prefix)[1])
        else:
            self.log_warning(f'Network for VLAN <a href="{vlan.get_absolute_url()}">{vlan.name}</a> is missing IPv6 Prefix')

        try:
            router = IPAddress.objects.get(address=gw4)
        except IPAddress.DoesNotExist:
            self.log_warning(f'Router not found for VLAN <a href="{vlan.get_absolute_url()}">{vlan.name}</a>')
            router = "r1.tele"

        vlan_name = vlan.name
        if 'gondul-name:' in vlan.description:
            override = vlan.description.split('gondul-name:')[1].split()[0]
            self.log_info(f'Overriding management vlan name with: {override} (was: {vlan_name})')
            vlan_name = override
        vlan_name += f".{router}"

        data = json.dumps([{
            "name": vlan_name,
            "subnet4": subnet4,
            "subnet6": subnet6,
            "gw4": gw4,
            "gw6": gw6,
            "router": router,
            "vlan": vlan.vid,
        }])

        req = requests.post(
            f"{GONDUL_URL}/api/write/networks",
            auth=gondul_auth,
            headers={'content-type': 'application/json'},
            data=data,
        )

        if req.ok:
            self.log_success(f"Gondul said (HTTP {req.status_code}): {req.text}")
        else:
            self.log_failure(f"Gondul said HTTP {req.status_code} and {req.text}")

    def device_to_gondul(self, device: Device):
        self.log_info(f"Posting {device.name} to Gondul")

        # Find distro and distro port through the cable connected on uplink ae.
        # Assuming the uplink AE is always named 'ae0'.
        uplink_ae: Interface = device.interfaces.get(name="ae0")

        first_ae_interface: Interface = uplink_ae.member_interfaces.first()
        cable: Cable = first_ae_interface.cable
        # Assuming we only have one entry in the cable termination list.
        distro_interface: Interface = cable.a_terminations[0]
        distro = distro_interface.device

        mgmt_vlan = uplink_ae.tagged_vlans.first()
        # Could consider filtering interfaces for: filter(Q(is_management=True) | Q(description__icontains="management")).first()
        # to make sure we only pick management VLANs

        mgmt_vlan_name = mgmt_vlan.name
        if 'gondul-name:' in mgmt_vlan.description:
            override = mgmt_vlan.description.split('gondul-name:')[1].split()[0]
            self.log_info(f'Overriding management vlan name with: {override} (was: {mgmt_vlan_name})')
            mgmt_vlan_name = override

        # add name of router to vlan name
        router = "r1.tele"
        mgmt_vlan_name += f".{router}"

        data = json.dumps([{
            # "community": "", # Not implemented
            "tags": list(device.tags.all()),
            "distro_name": distro.name,
            "distro_phy_port": distro_interface.name,  # TODO: always .0 ?
            "mgmt_v4_addr": str(device.primary_ip4.address.ip) if device.primary_ip4 is not None else None,
            "mgmt_v6_addr": str(device.primary_ip6.address.ip) if device.primary_ip6 is not None else None,
            "mgmt_vlan": mgmt_vlan_name,
            # "placement": "", # Not implemented
            # "poll_frequency": "", # Not implemented
            "sysname": device.name,
            # "traffic_vlan": "", # Not implemented
            # "deleted": False,  # Not implemented
        }])

        gondul_auth = HTTPBasicAuth(GONDUL_USERNAME, GONDUL_PASSWORD)
        req = requests.post(
            f"{GONDUL_URL}/api/write/switches",
            auth=gondul_auth,
            headers={'content-type': 'application/json'},
            data=data,
        )

        if req.ok:
            self.log_success(f"Gondul said (HTTP {req.status_code}): {req.text}")
        else:
            self.log_failure(f"Gondul said HTTP {req.status_code} and {req.text}")

    def run(self, data, commit):

        device: Device = data['device']
        """
        vlan: VLAN = data['vlan']
        prefix_v4: Prefix = data['prefix_v4']
        prefix_v6: Prefix = data['prefix_v6']
        """

        """
            if prefix_v4 is None:
                self.log_info(f"v4 not provided, default")
        """

        if not device.primary_ip4 and not device.primary_ip6:
            self.log_failure(f'Device <a href="{device.get_absolute_url()}">{device.name}</a> is missing primary IPv4 and IPv6 address.')
            return

        vlan: VLAN = None
        prefix_v4: Prefix = None
        if device.primary_ip4:
            prefix_v4 = Prefix.objects.get(NetContainsOrEquals(F('prefix'), str(device.primary_ip4.address)))
            vlan = prefix_v4.vlan
        else:
            self.log_warning(f'Device <a href="{device.get_absolute_url()}">{device.name}</a> is missing primary IPv4 address.')

        prefix_v6: Prefix = None
        if device.primary_ip6:
            prefix_v6 = Prefix.objects.get(NetContainsOrEquals(F('prefix'), str(device.primary_ip6.address)))
            vlan = prefix_v6.vlan
        else:
            self.log_warning(f'Device <a href="{device.get_absolute_url()}">{device.name}</a> is missing primary IPv6 address.')

        if prefix_v4 is not None and prefix_v6 is not None and prefix_v4.vlan != prefix_v6.vlan:
            self.log_failure(f'VLANs differ for the IPv4 and IPv6 addresses.')
            return

        self.network_to_gondul(vlan, prefix_v4, prefix_v6)

        self.log_success("All good, sending to Gondul")

        self.device_to_gondul(device)
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
        description = """
            Can be done for a single network/device or a full sync. Note that this will not do 'renames' of devices, so it is best used for updating device information.
            If a device is selected, it will also sync the required networks as long as they are set up correctly (Primary IP addresses for the Switch & VLAN configured for the Prefix of those IP Addresses).
        """
        field_order = ['site_name', 'switch_count', 'switch_model']

    switch = ObjectVar(
        description="Switch",
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
            gw4 = ipaddress.IPv4Network(prefix_v4.prefix)[1].exploded
        else:
            self.log_warning(f'Network for VLAN <a href="{vlan.get_absolute_url()}">{vlan.name}</a> is missing IPv4 Prefix')

        if prefix_v6:
            subnet6 = str(prefix_v6.prefix)
            gw6 = ipaddress.IPv6Network(prefix_v6.prefix)[1].exploded
        else:
            self.log_warning(f'Network for VLAN <a href="{vlan.get_absolute_url()}">{vlan.name}</a> is missing IPv6 Prefix')

        try:
            router = IPAddress.objects.get(address=gw4)
        except IPAddress.DoesNotExist:
            self.log_warning(f'Router not found for VLAN <a href="{vlan.get_absolute_url()}">{vlan.name}</a>')

        data = json.dumps([{
            "name": vlan.name,
            "subnet4": subnet4,
            "subnet6": subnet6,
            "gw4": gw4,
            "gw6": gw6,
            "router": router,
            "vlan": vlan.vid,
        }])

        req = requests.post(
            f"{GONDUL_URL}/api/write/networks",
            data=data,
            headers={'content-type': 'application/json'},
            auth=gondul_auth,
        )

        if req.ok:
            self.log_success(f"Gondul said (HTTP {req.status_code}): {req.text}")
        else:
            self.log_failure(f"Gondul said HTTP {req.status_code} and {req.text}")

    def device_to_gondul(self, device: Device):
        self.log_info(f"Posting {device.name} to Gondul")
 
        gondul_auth = HTTPBasicAuth(GONDUL_USERNAME, GONDUL_PASSWORD)

        data = json.dumps([
        ])

        req = requests.post(
            f"{GONDUL_URL}/api/write/switches",
            data=data,
            headers={'content-type': 'application/json'},
            auth=gondul_auth,
        )

        if req.ok:
            self.log_success(f"Gondul said (HTTP {req.status_code}): {req.text}")
        else:
            self.log_failure(f"Gondul said HTTP {req.status_code} and {req.text}")

    def run(self, data, commit):

        switch: Device = data['switch']
        """
        vlan: VLAN = data['vlan']
        prefix_v4: Prefix = data['prefix_v4']
        prefix_v6: Prefix = data['prefix_v6']
        """

        """
            if prefix_v4 is None:
                self.log_info(f"v4 not provided, default")
        """

        if not (switch.primary_ip4 or switch.primary_ip6):
            self.log_failure(f'Switch <a href="{switch.get_absolute_url()}">{switch.name}</a> is missing primary IPv4 or IPv6 address.')
            return

        prefix_v4 = Prefix.objects.get(NetContainsOrEquals(F('prefix'), str(switch.primary_ip4.address)))
        prefix_v6 = Prefix.objects.get(NetContainsOrEquals(F('prefix'), str(switch.primary_ip6.address)))

        vlan = prefix_v6.vlan

        if prefix_v4.vlan != prefix_v6.vlan:
            self.log_failure(f'VLANs differ for the IPv4 and IPv6 addresses.')
            return

        self.network_to_gondul(vlan, prefix_v4, prefix_v6)

        self.log_success("All good, sending to Gondul")

        self.device_to_gondul(switch)

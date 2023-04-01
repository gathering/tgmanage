import os

from django.contrib.contenttypes.models import ContentType
from django.db.models import F
from django.utils.text import slugify

from dcim.choices import DeviceStatusChoices, InterfaceModeChoices, InterfaceTypeChoices, SiteStatusChoices
from dcim.models import Cable, CableTermination, Device, DeviceRole, DeviceType, Interface, Manufacturer, Site
from extras.scripts import *
from ipam.models import IPAddress, Prefix, VLAN
from ipam.lookups import NetHostContained

import ipaddress
import json
import re
import requests
from requests.models import HTTPBasicAuth

class GondulConfigError(Exception):
    def __init__(self, msg):
        self.message = msg
        super().__init__(self.message)


GONDUL_CONFIG_FILE = os.getenv("GONDUL_CONFIG_FILE_PATH", "/etc/netbox/scripts/gondul.json")

class Gondul(object):
    url = ""
    username = ""
    password = ""

    def __init__(self, url, username, password) -> None:
        self.url = url
        self.username = username
        self.password = password

    @classmethod
    def read_config_from_file(cls, path):
        with open(path, 'r') as f:
            conf = json.loads(f.read())

            try:
                url = conf['url']
                username = conf['username']
                password = conf['password']
                return Gondul(url, username, password)
            except KeyError as e:
                raise GondulConfigError(f"Missing Gondul Configuration key: {e} in {path}")

    def gondul_auth(self):
        return HTTPBasicAuth(self.username, self.password)

    def gondul_post(self, path, data):
        return requests.post(
            f"{self.url}{path}",
            auth=self.gondul_auth(),
            headers={'content-type': 'application/json'},
            data=json.dumps(data),
        )

    def update_networks(self, networks):
        return self.gondul_post("/api/write/networks", networks)

    def update_switches(self, switches):
        return self.gondul_post("/api/write/switches", switches)


class Netbox2Gondul(Script):
    class Meta:
        name = "Sync NetBox to Gondul"
        description = re.sub(r'^\s*', '', """
            Can be done for a single network/device or a full sync. Note that this will not do 'renames' of devices, so it is best used for updating device information.
            If a device is selected, it will also sync the required networks as long as they are set up correctly (Primary IP addresses for the Device & VLAN configured for the Prefix of those IP Addresses).
        """)

    device = MultiObjectVar(
        label="Switches",
        description="Switches to update in Gondul. Leave empty to sync all devices and networks.",
        model=Device,
        required=False,
    )

    _gondul = None

    def networks_to_gondul(self, networks):
        self.log_info(f"Posting {len(networks)} networks to Gondul")
        req = self._gondul.update_networks(networks)

        if req.ok:
            self.log_success(f"Gondul said (HTTP {req.status_code}): {req.text}")
        else:
            self.log_failure(f"Gondul said HTTP {req.status_code} and {req.text}")

    def network_to_gondul_format(self, vlan: VLAN, prefix_v4: Prefix, prefix_v6: Prefix):
        self.log_info(f"Preparing {vlan.name} for Gondul")

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
            router = str(IPAddress.objects.get(address=gw4))
        except IPAddress.DoesNotExist:
            self.log_warning(f'Router not found for VLAN <a href="{vlan.get_absolute_url()}">{vlan.name}</a>')
            router = "r1.tele"

        vlan_name = vlan.name
        if vlan.custom_fields.filter(name='gondul_name').count() == 1 and vlan.cf['gondul_name']:
            override = vlan.cf['gondul_name']
            self.log_info(f'Overriding management vlan name with: {override} (was: {vlan_name})')
            vlan_name = override
        return {
            "name": vlan_name,
            "subnet4": subnet4,
            "subnet6": subnet6,
            "gw4": gw4,
            "gw6": gw6,
            "router": router,
            "vlan": vlan.vid,
        }

    def switches_to_gondul(self, switches):
        self.log_info(f"Posting {len(switches)} switches to Gondul")

        req = self._gondul.update_switches(switches)

        if req.ok:
            self.log_success(f"Gondul said (HTTP {req.status_code}): {req.text}")
        else:
            self.log_failure(f"Gondul said HTTP {req.status_code} and {req.text}")

    def device_to_gondul_format(self, device: Device):
        # Find distro and distro port through the cable connected on uplink ae.
        # Assuming the uplink AE is always named 'ae0'.
        uplink_ae: Interface = device.interfaces.get(name="ae0")

        first_ae_interface: Interface = uplink_ae.member_interfaces.first()
        cable: Cable = first_ae_interface.cable
        # Assuming we only have one entry in the cable termination list.
        distro_interface: Interface = cable.a_terminations[0]
        distro = distro_interface.device

        # This is the same way as we fetch mgmt vlan in the main run() function.
        # We could pass it in directly to device_to_gondul().
        mgmt_ip_addr = device.primary_ip4 if device.primary_ip4 is not None else device.primary_ip6
        mgmt_prefix = Prefix.objects.get(NetHostContained(F('prefix'), str(mgmt_ip_addr)))
        mgmt_vlan = mgmt_prefix.vlan

        mgmt_vlan_name = mgmt_vlan.name
        if mgmt_vlan.custom_fields.filter(name='gondul_name').count() == 1 and mgmt_vlan.cf['gondul_name']:
            override = mgmt_vlan.cf['gondul_name']
            self.log_info(f'Overriding management vlan name with: {override} (was: {mgmt_vlan_name})')
            mgmt_vlan_name = override

        traffic_network = None
        traffic_vlan_name = None
        try:
            traffic_vlan = VLAN.objects.get(name=device.name)
            traffic_prefix_v4 = Prefix.objects.get(vlan=traffic_vlan, prefix__family=4)
            traffic_prefix_v6 = Prefix.objects.get(vlan=traffic_vlan, prefix__family=6)
            traffic_vlan_name = traffic_vlan.name

            traffic_network = self.network_to_gondul_format(traffic_vlan, traffic_prefix_v4, traffic_prefix_v6)
        except VLAN.DoesNotExist:
            pass

        return {
            # "community": "", # Not implemented
            "tags": [tag.slug for tag in list(device.tags.all())],
            "distro_name": distro.name,
            "distro_phy_port": f"{distro_interface.name}.0",
            "mgmt_v4_addr": str(device.primary_ip4.address.ip) if device.primary_ip4 is not None else None,
            "mgmt_v6_addr": str(device.primary_ip6.address.ip) if device.primary_ip6 is not None else None,
            "mgmt_vlan": mgmt_vlan_name,
            # "placement": "", # Not implemented
            # "poll_frequency": "", # Not implemented
            "sysname": device.name,
            "traffic_vlan": traffic_vlan_name,
            # "deleted": False,  # Not implemented
        }, traffic_network

    def run(self, data, commit):
        input_devices: list[Type[Device]] = data['device']

        if len(input_devices) == 0:
            input_devices = Device.objects.all()

        networks = []
        switches = []

        # sanity check
        for device in input_devices:
            if not device.primary_ip4 and not device.primary_ip6:
                self.log_failure(f'Device <a href="{device.get_absolute_url()}">{device.name}</a> is missing primary IPv4 and IPv6 address.')
                return

            vlan: VLAN = None
            prefix_v4: Prefix = None
            if device.primary_ip4:
                prefix_v4 = Prefix.objects.get(NetHostContained(F('prefix'), str(device.primary_ip4)))
                vlan = prefix_v4.vlan
            else:
                self.log_warning(f'Device <a href="{device.get_absolute_url()}">{device.name}</a> is missing primary IPv4 address.')

            prefix_v6: Prefix = None
            if device.primary_ip6:
                prefix_v6 = Prefix.objects.get(NetHostContained(F('prefix'), str(device.primary_ip6)))
                vlan = prefix_v6.vlan
            else:
                self.log_warning(f'Device <a href="{device.get_absolute_url()}">{device.name}</a> is missing primary IPv6 address.')

            if prefix_v4 is not None and prefix_v6 is not None and prefix_v4.vlan != prefix_v6.vlan:
                self.log_failure(f'VLANs differ for the IPv4 and IPv6 addresses.')
                return


            networks.append(self.network_to_gondul_format(vlan, prefix_v4, prefix_v6))
            switch, traffic_network = self.device_to_gondul_format(device)
            if traffic_network:
                networks.append(traffic_network)
            switches.append(switch)

        self.log_success("All good, sending to Gondul")
        self._gondul = Gondul.read_config_from_file(GONDUL_CONFIG_FILE)

        self.networks_to_gondul(networks)
        self.switches_to_gondul(switches)

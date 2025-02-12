from extras.scripts import *
from django.core.exceptions import ValidationError

from dcim.models import Device, DeviceType, Location, DeviceRole, Site, Interface
from dcim.choices import InterfaceModeChoices, InterfaceTypeChoices

from ipam.models import VLANGroup, VLAN, Role, Prefix, IPAddress
from ipam.choices import PrefixStatusChoices


DEFAULT_SITE = Site.objects.get(name='Vikingskipet')
DEFAULT_DEVICE_TYPE = DeviceType.objects.get(model='EX2200-48T-4G')
DEFAULT_DEVICE_ROLE = DeviceRole.objects.get(slug='access-switch')
DEFAULT_TG_DNS_SUFFIX = "tg25.tg.no"

# VLAN Group to allocate VLANs from
FABRIC_VLAN_GROUP = VLANGroup.objects.get(slug='client-vlans')

# Vlan role for fabric clients
FABRIC_CLIENTS_ROLE = Role.objects.get(slug='clients')

# Client networks allocated from here
FABRIC_V4_CLIENTS_PREFIX = Prefix.objects.get(prefix='10.25.0.0/16')
FABRIC_V6_CLIENTS_PREFIX = Prefix.objects.get(prefix='2a06:5844:e::/48')

# Switch mgmt allocates from here
FABRIC_V4_JUNIPER_MGMT_PREFIX = Prefix.objects.get(prefix='185.110.149.0/25')
FABRIC_V6_JUNIPER_MGMT_PREFIX = Prefix.objects.get(prefix='2a06:5841:f::/64')

UPLINK_PORTS = {
    'EX2200-48T-4G': ["ge-0/0/45", "ge-0/0/46", "ge-0/0/47", "ge-0/0/48"],
}

def generatePrefix(prefix, length):
    firstPrefix = prefix.get_first_available_prefix()
    out = list(firstPrefix.subnet(length, count=1))[0]
    return out

class CreateSwitch(Script):
    class Meta:
        name = "Create Switch"
        description = "Provision a new switch"
        commit_default = True
        field_order = ['site_name', 'switch_count', 'switch_model']
        fieldsets = ""
        scheduling_enabled = False

    switch_name = StringVar(
        description = "Switch name. Remember, e = access switch, d = distro switch",
        required = True,
        default = "e1.test" # default during development
    )
    device_type = ObjectVar(
        description = "Device model",
        model = DeviceType,
        default = DEFAULT_DEVICE_TYPE.id,
    )
    device_role = ObjectVar(
        description = "Device role",
        model = DeviceRole,
        default = DEFAULT_DEVICE_ROLE.id,
    )
    location = ObjectVar(
        model = Location,
        required = True,
        default = Location.objects.get(name="Ringen") # Default during development
    )

    def run(self, data, commit):
        if not data['switch_name'].startswith("e") and not data['switch_name'].startswith("d"):
            raise ValidationError("Switch name must start whit e or d")

        switch = Device(
            name = data['switch_name'],
            device_type = data['device_type'],
            location = data['location'],
            role = data['device_role'],
            site = DEFAULT_SITE
        )
        switch.save()
        self.log_info("Created switch")

        mgmt_interface_name = "irb"
        if switch.device_type.model == "EX2200-48T-4G":
            mgmt_interface_name = "vlan"

        mgmt_vlan_interface = Interface.objects.create(
            device=switch,
            name=f"{mgmt_interface_name}.{FABRIC_V4_JUNIPER_MGMT_PREFIX.vlan.id}",
            description = f'X: Mgmt',
            type=InterfaceTypeChoices.TYPE_VIRTUAL,
            mode=InterfaceModeChoices.MODE_TAGGED,
        )

        v4_mgmt_addr = IPAddress.objects.create(
            address=FABRIC_V4_JUNIPER_MGMT_PREFIX.get_first_available_ip(),
            dns_name=f"{switch.name}.{DEFAULT_TG_DNS_SUFFIX}"

        )
        v6_mgmt_addr = IPAddress.objects.create(
            address=FABRIC_V6_JUNIPER_MGMT_PREFIX.get_first_available_ip(),
            dns_name=f"{switch.name}.{DEFAULT_TG_DNS_SUFFIX}"
        )

        mgmt_vlan_interface.ip_addresses.add(v4_mgmt_addr)
        mgmt_vlan_interface.ip_addresses.add(v6_mgmt_addr)
        switch.primary_ip4 = v4_mgmt_addr
        switch.primary_ip6 = v6_mgmt_addr
        switch.save()
        self.log_info("Allocated and assigned mgmt addresses on switch")

        vid = FABRIC_VLAN_GROUP.get_next_available_vid()
        vlan = VLAN.objects.create(
            name = switch.name,
            group = FABRIC_VLAN_GROUP,
            role = FABRIC_CLIENTS_ROLE,
            vid = vid
        )
        vlan.save()
        self.log_info("Created VLAN")

        interfaces = list(Interface.objects.filter(device=switch, type=InterfaceTypeChoices.TYPE_1GE_FIXED))
        if len(interfaces) == 0:
            self.log_error(f"no interfaces found")

        for interface in interfaces:
            if interface.name in UPLINK_PORTS.get(switch.device_type.model, []):
                continue
            interface.mode = 'access'
            interface.untagged_vlan = vlan
            interface.description = "C: Clients"
            interface.save()

        self.log_info("Configured traffic vlan on all client ports")

        v6_prefix = Prefix.objects.create(
            prefix = generatePrefix(FABRIC_V6_CLIENTS_PREFIX, 64),
            status = PrefixStatusChoices.STATUS_ACTIVE,
            role = FABRIC_CLIENTS_ROLE,
            vlan = vlan
        )

        v4_prefix = Prefix.objects.create(
            prefix = generatePrefix(FABRIC_V4_CLIENTS_PREFIX, 26),
            status = PrefixStatusChoices.STATUS_ACTIVE,
            role = FABRIC_CLIENTS_ROLE,
            vlan = vlan
        )
        self.log_info("Allocated traffic prefixes")

        self.log_success(f"✅ Script completed successfully.")
        self.log_success(f"🔗 Switch:     <a href=\"{switch.get_absolute_url()}\">{switch}</a>")
        self.log_success(f"🔗 v6 Prefix:  <a href=\"{v6_prefix.get_absolute_url()}\">{v6_prefix}</a>")
        self.log_success(f"🔗 v4 Prefix:  <a href=\"{v4_prefix.get_absolute_url()}\">{v4_prefix}</a>")
        self.log_success(f"🔗 VLAN:       <a href=\"{vlan.get_absolute_url()}\">{vlan}</a>")
        self.log_success(f"⚠️ <strong>️Fabric config must be deployed before switch can be fapped.</strong>")

script = CreateSwitch

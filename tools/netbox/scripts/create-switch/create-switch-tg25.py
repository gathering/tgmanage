from extras.scripts import *
from django.core.exceptions import ValidationError
from django.contrib.contenttypes.models import ContentType

from dcim.models import Cable, CableTermination, Device, DeviceType, Location, DeviceRole, Site, Interface
from dcim.choices import InterfaceModeChoices, InterfaceTypeChoices

from ipam.models import VLANGroup, VLAN, Role, Prefix, IPAddress
from ipam.choices import PrefixStatusChoices

DEFAULT_SITE = Site.objects.get(name='Vikingskipet')
DEFAULT_DEVICE_TYPE = DeviceType.objects.get(model='EX2200-48T-4G')
DEFAULT_DEVICE_ROLE = DeviceRole.objects.get(slug='access-switch')
DEFAULT_TG_DNS_SUFFIX = "tg25.tg.no"
DEFAULT_UPLINK_SWITCH = Device.objects.get(name='d1.ring')

DEVICE_ROLE_LEAF = "leaf"
DEVICE_ROLE_DISTRO = "distro"
DEVICE_ROLE_UTSKUTT_DISTRO = "utskutt-distro"

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
    'EX2200-48T-4G': ["ge-0/0/44", "ge-0/0/45", "ge-0/0/46", "ge-0/0/47"],
}

UPLINK_TYPES = (
    (InterfaceTypeChoices.TYPE_10GE_SFP_PLUS, '10G SFP+'),
    (InterfaceTypeChoices.TYPE_1GE_FIXED, '1G RJ45'),
    (InterfaceTypeChoices.TYPE_10GE_FIXED, '10G RJ45')
)

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
    uplink_type = ChoiceVar(
        label = 'Uplink Type',
        required = True,
        description = "What type of interface should this switch be delivered on",
        choices = UPLINK_TYPES,
        default = InterfaceTypeChoices.TYPE_1GE_FIXED
    )
    destination_device_a = ObjectVar(
        description = "Uplink device (A)",
        required = True,
        model = Device,
        query_params = {
            'role': [DEVICE_ROLE_LEAF, DEVICE_ROLE_DISTRO, DEVICE_ROLE_UTSKUTT_DISTRO],
        },
        default = DEFAULT_UPLINK_SWITCH
    )
    destination_device_b = ObjectVar(
        description = "If connected to leaf pair - Uplink device (B)",
        required = False,
        model = Device,
        query_params = {
            'role': [DEVICE_ROLE_LEAF],
        },
    )
    # If leaf pair we assume same port. This input only cares about cases with single device.
    destination_interfaces = MultiObjectVar(
        description="Destination interface(s). \n\n IF You're looking at d1.ring: ge-{PLACEMENT}/x/x. Placements: 0 = South, 1 = Log, 2 = Swing, 3 = North, 4 = noc, 5 = tele",
        model=Interface,
        query_params={
            'device_id': '$destination_device_a',
            'occupied': False,
            'type': '$uplink_type'
        }
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

        uplink_description = f"B: {data['destination_device_a'].name}"
        if data['destination_device_b']:
            uplink_description = f"B: {data['destination_device_a'].name} / {data['destination_device_b'].name} - ae{vlan.id}"

        uplink_ae = Interface.objects.create(
            device=switch,
            name="ae0",
            description = uplink_description,
            type = InterfaceTypeChoices.TYPE_LAG,
            mode = InterfaceModeChoices.MODE_TAGGED,
        )


        if data['destination_device_a'].role == DEVICE_ROLE_UTSKUTT_DISTRO:
            self.log_debug(f"{ data['destination_device_a']} is utskutt-distro")
            # TODO make sure we add traffic vlan on AE between distro and utskutt-distro as well.

        uplink_ae.tagged_vlans.add(FABRIC_V4_JUNIPER_MGMT_PREFIX.vlan.id)
        uplink_ae.tagged_vlans.add(vlan.id)

        ## We only need this if not connected to leaf (since they are provisioned using AVD)
        if data['destination_device_a'].role != DEVICE_ROLE_LEAF:
            destination_ae = Interface.objects.create(
                device=data['destination_device_a'],
                name=f"ae{vlan.id}",
                description = f'B: {switch.name} ae0',
                type=InterfaceTypeChoices.TYPE_LAG,
                mode=InterfaceModeChoices.MODE_TAGGED,
            )
            destination_ae.save()
            destination_ae.tagged_vlans.add(FABRIC_V4_JUNIPER_MGMT_PREFIX.vlan.id)
            destination_ae.tagged_vlans.add(vlan.id)
            self.log_debug(f"Created destination AE <a href=\"{destination_ae.get_absolute_url()}\">{destination_ae}</a>")

            ## TODO support leaf pair
            num_uplinks = len(data['destination_interfaces'])
            uplink_interfaces = list(Interface.objects.filter(device=switch, type=data['uplink_type']))
            if len(uplink_interfaces) < 1:
                raise AbortScript(f"You chose a device type without any {data['uplink_type']} interfaces! Pick another model :)")

            interface_type = ContentType.objects.get_for_model(Interface)
            interfaces_filtered = [interface for interface in uplink_interfaces if interface.name in UPLINK_PORTS.get(switch.device_type.model, [])]
            for uplink_num in range(0, num_uplinks):
                a_interface = data['destination_interfaces'][uplink_num]
                b_interface = interfaces_filtered[uplink_num]

                self.log_debug(f"Connecting: {data['destination_device_a']} - {a_interface} to {switch} - {b_interface}")

                a_interface.description = f'G: {switch.name} {b_interface.name} (ae0)'
                b_interface.description = f"G: {data['destination_device_a'].name} {a_interface.name} (ae{vlan.id})"

                b_interface.lag = uplink_ae
                b_interface.save()

                a_interface.lag = destination_ae
                a_interface.save()

                cable = Cable.objects.create()
                a = CableTermination.objects.create(
                    cable=cable,
                    cable_end='A',
                    termination_id=a_interface.id,
                    termination_type=interface_type,
                )
                b = CableTermination.objects.create(
                    cable_end='B',
                    cable=cable,
                    termination_id=b_interface.id,
                    termination_type=interface_type,
                )
                cable = Cable.objects.get(id=cable.id)
                # https://github.com/netbox-community/netbox/discussions/10199
                cable._terminations_modified = True
                cable.save()


        self.log_success(f"✅ Script completed successfully.")
        self.log_success(f"🔗 Switch:     <a href=\"{switch.get_absolute_url()}\">{switch}</a>")
        self.log_success(f"🔗 v6 Prefix:  <a href=\"{v6_prefix.get_absolute_url()}\">{v6_prefix}</a>")
        self.log_success(f"🔗 v4 Prefix:  <a href=\"{v4_prefix.get_absolute_url()}\">{v4_prefix}</a>")
        self.log_success(f"🔗 VLAN:       <a href=\"{vlan.get_absolute_url()}\">{vlan}</a>")
        self.log_success(f"⚠️ <strong>️Fabric config must be deployed before switch can be fapped.</strong>")

script = CreateSwitch

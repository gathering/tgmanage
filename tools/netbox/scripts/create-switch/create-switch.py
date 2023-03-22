from django.contrib.contenttypes.models import ContentType
from django.utils.text import slugify

from dcim.choices import DeviceStatusChoices, InterfaceModeChoices, InterfaceTypeChoices, SiteStatusChoices
from dcim.models import Cable, CableTermination, Device, DeviceRole, DeviceType, Interface, Manufacturer, Site
from extras.models import Tag
from extras.scripts import *
from ipam.models import IPAddress, Prefix, VLAN, VLANGroup

# Used for getting existing types/objects from Netbox.
DISTRIBUTION_SWITCH_DEVICE_ROLE = 'distribution-switch' # match the name or the slug
ROUTER_DEVICE_ROLE = 'router'
CORE_DEVICE_ROLE = 'core'
ACCESS_SWITCH_DEVICE_ROLE = DeviceRole.objects.get(name='Access Switch')
DEFAULT_SITE = Site.objects.first()  # TODO: pick default site ?

class CreateSwitch(Script):

    class Meta:
        name = "Create Switch"
        description = "Provision a new switch"
        field_order = ['site_name', 'switch_count', 'switch_model']

    switch_name = StringVar(
        description="Switch name"
    )
    device_type = ObjectVar(
        description="Device model",
        model=DeviceType,
    )
    role = ObjectVar(
        description="Device role",
        model=DeviceRole,
        default=ACCESS_SWITCH_DEVICE_ROLE.id,
    )
    site = ObjectVar(
        description = "Site",
        model=Site,
        default=DEFAULT_SITE.id,
    )
    destination_device = ObjectVar(
        description = "Destination/uplink",
        model=Device,
        query_params={
            'role': [DISTRIBUTION_SWITCH_DEVICE_ROLE, ROUTER_DEVICE_ROLE, CORE_DEVICE_ROLE],
        },
    )
    destination_interfaces = MultiObjectVar(
        description="Destination interface(s)",
        model=Interface,
        query_params={
            'device_id': '$destination_device',  
            # ignore interfaces aleady cabled https://github.com/netbox-community/netbox/blob/v3.4.5/netbox/dcim/filtersets.py#L1225
            'cabled': False,
        }
    )
    vlan_group = ObjectVar(
        label="VLAN Group",
        description="VLAN Group",
        model=VLANGroup,
    )
    vlan_id = IntegerVar(
        label="VLAN ID",
        description="Auto-assigned if not specified. Make sure it is available if you provide it.",
        required=False,
        default='',
    )
    mgmt_vlan = ObjectVar(
        description="Management VLAN",
        model=VLAN,
        query_params={
            'vid': [666, 667],
        }
    )
    mgmt_prefix_v4 = ObjectVar(
        description="IPv4 Prefix to assign a management IP Address from",
        model=Prefix,
        query_params={
            'family': 4,
            'vlan_id': '$mgmt_vlan'
        }
    )
    mgmt_prefix_v6 = ObjectVar(
        description="IPv6 Prefix to assign a management IP Address from",
        model=Prefix,
        query_params={
            'family': 6,
            'vlan_id': '$mgmt_vlan'
        }
    )
    tags = MultiObjectVar(
        description="Tags to be sent to Gondul. These are used for templating, so be sure what they do.",
        model=Tag,
        required=False,
    )

    def run(self, data, commit):
        mgmt_vlan = data['mgmt_vlan']

        # Create the new switch
        switch = Device(
            name=data['switch_name'],
            device_type=data['device_type'],
            device_role=data['role'],
            site=data['site'],
        )
        switch.save()
        self.log_success(f"Created new switch: <a href=\"{switch.get_absolute_url()}\">{switch}</a>")

        vlan_group = data['vlan_group']
        vid = vlan_group.get_next_available_vid()
        # use provided vid if specified.
        if data['vlan_id']:
            vid = data['vlan_id']
        vlan = VLAN.objects.create(
            name=switch.name,
            group=vlan_group,
            vid=vid
        )
        vlan.save()

        mgmt_vlan_interface = Interface.objects.create(
            device=switch,
            name=f"vlan.{mgmt_vlan.vid}",
            type=InterfaceTypeChoices.TYPE_VIRTUAL,
            mode=InterfaceModeChoices.MODE_TAGGED,
        )
        mgmt_vlan_interface.tagged_vlans.add(mgmt_vlan.id)

        uplink_ae = Interface.objects.create(
            device=switch,
            name="ae0",
            description=data['destination_device'].name,
            type=InterfaceTypeChoices.TYPE_LAG,
            mode=InterfaceModeChoices.MODE_TAGGED,
        )
        uplink_ae.tagged_vlans.add(mgmt_vlan.id)
        uplink_vlan = Interface.objects.create(
            device=switch,
            name="ae0.0",
            description=data['destination_device'].name,
            type=InterfaceTypeChoices.TYPE_VIRTUAL,
            parent=uplink_ae,
        )
        destination_ae = Interface.objects.create(
            device=data['destination_device'],
            name=f"ae{vlan.vid}",
            description=switch.name,
            type=InterfaceTypeChoices.TYPE_LAG,
            mode=InterfaceModeChoices.MODE_TAGGED,
        )
        destination_ae.tagged_vlans.add(mgmt_vlan.id)
        destination_vlan = Interface.objects.create(
            device=data['destination_device'],
            name=f"vlan.{vid}",
            description=switch.name,
            type=InterfaceTypeChoices.TYPE_VIRTUAL,
            parent=destination_ae,
        )
        self.log_success("Created AE and VLAN interfaces for both ends")

        v4_mgmt_addr = IPAddress.objects.create(
            address=data['mgmt_prefix_v4'].get_first_available_ip(),
        )
        v6_mgmt_addr = IPAddress.objects.create(
            address=data['mgmt_prefix_v6'].get_first_available_ip(),
        )
        mgmt_vlan_interface.ip_addresses.add(v4_mgmt_addr)
        mgmt_vlan_interface.ip_addresses.add(v6_mgmt_addr)
        switch.primary_ip4 = v4_mgmt_addr
        switch.primary_ip6 = v6_mgmt_addr
        switch.save()

        num_uplinks = len(data['destination_interfaces'])
        interfaces = list(Interface.objects.filter(device=switch).exclude(type=InterfaceTypeChoices.TYPE_VIRTUAL).exclude(type=InterfaceTypeChoices.TYPE_LAG))
        interface_type = ContentType.objects.get_for_model(Interface)
        for uplink_num in range(0, num_uplinks):
            # mark last ports as uplinks
            a_interface = data['destination_interfaces'][::-1][uplink_num]
            b_interface = interfaces[(uplink_num * -1) -1]

            # Configure uplink as AE0
            b_interface.lag = uplink_ae
            b_interface.save()

            # Configure downlink on destination
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
            self.log_success(f"Cabled {data['destination_device']} {a_interface} to {switch} {b_interface}")

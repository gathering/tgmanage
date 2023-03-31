from django.contrib.contenttypes.models import ContentType
from django.utils.text import slugify

from dcim.choices import DeviceStatusChoices, InterfaceModeChoices, InterfaceTypeChoices, SiteStatusChoices
from dcim.models import Cable, CableTermination, Device, DeviceRole, DeviceType, Interface, Manufacturer, Site
from extras.models import Tag
from extras.scripts import *
from ipam.models import IPAddress, Prefix, VLAN, VLANGroup, Role
from ipam.choices import PrefixStatusChoices, IPAddressFamilyChoices
import random

from utilities.exceptions import AbortScript

# self.log_success for successfull creation
# self.log_info for FYI information

# Todo:
# * Tag switch based on this so config in templates is correct, see tags in tech-templates
#   * https://github.com/gathering/tech-templates
# * We should be able to choose a VLAN that actually exists. This will make switch delivery on stand MUCH easier

# Used for getting existing types/objects from Netbox.
DISTRIBUTION_SWITCH_DEVICE_ROLE = 'distribution-switch' # match the name or the slug
ROUTER_DEVICE_ROLE = 'router'
CORE_DEVICE_ROLE = 'core'
ACCESS_SWITCH_DEVICE_ROLE = DeviceRole.objects.get(name='Access Switch')
DEFAULT_SITE = Site.objects.get(slug='ring') # Site.objects.first()  # TODO: pick default site ?
DEFAULT_L1_SWITCH = Device.objects.get(name='d1.ring') # Site.objects.first()  # TODO: pick default site ?
DEFAULT_DEVICE_TYPE = DeviceType.objects.get(model='EX2200-48T') # Site.objects.first()  # TODO: pick default site ?
DEFAULT_NETWORK_TAGS = [Tag.objects.get(name='dhcp-client')]

UPLINK_TYPES = (
    (InterfaceTypeChoices.TYPE_10GE_SFP_PLUS, '10G SFP+'),
    (InterfaceTypeChoices.TYPE_1GE_FIXED, '1G CAT'),
    (InterfaceTypeChoices.TYPE_10GE_FIXED, '10G CAT')
)

LEVERANSE_TYPES = (
    (DeviceRole.objects.get(name='Access Switch'), 'Access Switch'),
    (DeviceRole.objects.get(name='Distribution Switch'), '"Utskutt" distro')
)

# Helper functions
def generateMgmtVlan(self, data):
        name = ''

        if data['leveranse'].name == "Access Switch":
            name += "edge-mgmt."
        elif data['leveranse'].name == "Distribution Switch":
            name += "distro-mgmt."
        else:
            raise AbortScript(f"Tbh, i only support access_switch and distro_switch in role")
        
        if "ring" in data['site'].slug or "floor" in data['site'].slug:
            name += data['site'].slug + ".r1.tele"
        elif "stand" in data['site'].slug:
            name += data['site'].slug + ".r1.stand"
        else:
            raise AbortScript(f"I only support creating switches in floor, ring or stand")

        return VLAN.objects.get(name=name)

# Cheeky, let's just do this hardcoded...
def getL3(self, data):
    if data['site'].slug == "ring":

        l3Term = Device.objects.get(
            name='r1.tele'
        )
        l3Intf = Interface.objects.get(
            device=l3Term.id,
            name='ae11'
        )

    elif data['site'].slug == "stand":
        l3Term = Device.objects.get(
            name='r1.stand'
        )
        l3Intf = "NOT IMPLEMENTED LOCAL VLAN OPTION. THIS USECAE DOESN'T WORK"

    elif data['site'].slug == "floor":
        l3Term = Device.objects.get(
            name='r1.tele'
        )
        l3Intf = Interface.objects.get(
            device=l3Term.id,
            name='ae10'
        )
    else:
        raise AbortScript(f"I only support creating switches in floor, ring or stand")

    self.log_info(f"l3Term: {l3Term}, l3Intf {l3Intf}")
    return l3Term, l3Intf

def generatePrefix(prefix, length):

    firstPrefix = prefix.get_first_available_prefix()
    out = list(firstPrefix.subnet(length, count=1))[0]
    return out

def getDeviceRole(type):
    if type == "Access Switch":
        out = DeviceRole.objects.get(name='Access Switch')
    elif type == "Distribution Switch":
        out = DeviceRole.objects.get(name='Distribution Switch')
    return out


class CreateSwitch(Script):

    class Meta:
        name = "Create Switch"
        description = "Provision a new switch"
        commit_default = False
        field_order = ['site_name', 'switch_count', 'switch_model']
        fieldsets = ""

    leveranse = ChoiceVar(
        label='Leveranse Type',
        description="Pick the appropriate leveranse type",
        choices=LEVERANSE_TYPES,
        #default=ACCESS_SWITCH_DEVICE_ROLE.id,
    )

    switch_name = StringVar(
        description="Switch name. Remember, e = access switch, d = distro switch"
    )

    uplink_type = ChoiceVar(
        label='Uplink Type',
        description="What type of interface should this switch be delivered on",
        choices=UPLINK_TYPES,
        default=InterfaceTypeChoices.TYPE_1GE_FIXED

    )
    device_type = ObjectVar(
        description="Device model",
        model=DeviceType,
        default=DEFAULT_DEVICE_TYPE.id,
    )

    site = ObjectVar(
        description = "Site",
        model=Site,
        default=DEFAULT_SITE,
    )

    destination_device = ObjectVar(
        description = "Destination/uplink",
        model=Device,
        default=DEFAULT_L1_SWITCH.id,
        query_params={
            'site_id': '$site',
            'role': [DISTRIBUTION_SWITCH_DEVICE_ROLE, ROUTER_DEVICE_ROLE, CORE_DEVICE_ROLE],
        },
    )
    destination_interfaces = MultiObjectVar(
        description="Destination interface(s). \n\n IF You're looking at d1.ring: ge-{PLACEMENT}/x/x. Placements: 0 = South, 1 = Log, 2 = Swing, 3 = North, 4 = noc, 5 = tele",
        model=Interface,
        query_params={
            'device_id': '$destination_device',  
            # ignore interfaces aleady cabled https://github.com/netbox-community/netbox/blob/v3.4.5/netbox/dcim/filtersets.py#L1225
            'cabled': False,
            'type': '$uplink_type'
        }
    )
    # I don't think we'll actually use this
    #vlan_id = IntegerVar(
    #    label="VLAN ID",
    #    description="NB: Only applicable for 'Access' deliveries! Auto-assigned if not specified. Make sure it is available if you provide it.",
    #    required=False,
    #    default='',
    #)
    device_tags = MultiObjectVar(
        label="Device tags",
        description="Tags to be sent to Gondul. These are used for templating, so be sure what they do.",
        model=Tag,
        required=False,
        query_params={
            "description__ic": "for:device",
        },
    )
    network_tags = MultiObjectVar(
        label="Network tags",
        description="Tags to be sent to Gondul. These are used for templating, so be sure what they do.",
        default=DEFAULT_NETWORK_TAGS,
        model=Tag,
        required=False,
        query_params={
            "description__ic": "for:network",
        },
    )

    nat = BooleanVar(
        label='NAT?',
        description="Should the network provided by the switch be NATed?"
    )


    def run(self, data, commit):


        self.log_success(f"{self.request.__dir__()}")
        self.log_success(f"{self.request.id.__dir__()}")
        self.log_success(f"{self.request.user}")
        self.log_success(f"{self.request.META}")
        # Unfuck shit
        # Choice var apparently only gives you a string, not an object.
        # Or i might be stooopid
        data['leveranse'] = getDeviceRole(data['leveranse'])

        # Let's start with assumptions!
        # We can generate the name of the vlan. No need to enter manually.
        # Possbly less confusing so.
        mgmt_vlan = generateMgmtVlan(self, data)
        # Make sure that site ang vlan group is the same. Since our vlan boundaries is the same as site
        vlan_group = VLANGroup.objects.get(slug=data['site'].slug)

        # Create the new switch
        switch = Device(
            name=data['switch_name'],
            device_type=data['device_type'],
            device_role=data['leveranse'],
            site=data['site'],
        )
        switch.save()
        for tag in data['device_tags']:
            switch.tags.add(tag)
        self.log_success(f"Created new switch: <a href=\"{switch.get_absolute_url()}\">{switch}</a>")



        # Only do this if access switch
        if data['leveranse'].name == "Access Switch":
            vid = vlan_group.get_next_available_vid()
            # use provided vid if specified.
            #if data['vlan_id']:
            #    vid = data['vlan_id']

            vlan = VLAN.objects.create(
                name=switch.name,
                group=vlan_group,
                vid=vid
            )
            vlan.save()

            for tag in data['network_tags']:
                vlan.tags.add(tag)

        # Only do this if access switch
        if data['leveranse'].name == "Access Switch":
            #
            # Prefixes Part
            #

            prefixes = Prefix.objects.filter(
                site = data['site'],
                status = PrefixStatusChoices.STATUS_CONTAINER,
                #family = IPAddressFamilyChoices.FAMILY_4,
                role = Role.objects.get(slug='crew').id
            )

            if len(prefixes) > 2 or len(prefixes) == 0:
                raise AbortScript(f"Got two or none prefixes. Run to Simen and ask for help!")

            # Doesn't support anything else than crew networks
            for prefix in prefixes:

                if prefix.family == 4:
                    v4_prefix = Prefix.objects.create(
                        prefix = generatePrefix(prefix, 26),
                        status = PrefixStatusChoices.STATUS_ACTIVE,
                        site = data['site'],
                        role = Role.objects.get(slug='crew'),
                        vlan = vlan
                    )
                    self.log_info(f"Created new IPv4 Prefix: {v4_prefix}")
                    if data['nat']:
                        nat = Tag.objects.get(slug='nat')
                        self.log_info(f"VLAN Id: {nat.name} - {nat.id}")
                        v4_prefix.tags.add(nat)

                elif prefix.family == 6:
                    v6_prefix = Prefix.objects.create(
                        prefix = generatePrefix(prefix, 64),
                        status = PrefixStatusChoices.STATUS_ACTIVE,
                        site = data['site'],
                        role = Role.objects.get(slug='crew'),
                        vlan = vlan
                    )
                    self.log_info(f"IPv6 Prefix: {v6_prefix}")
                    if data['nat']:
                        nat = Tag.objects.get(slug='nat')
                        self.log_info(f"VLAN Id: {nat.name} - {nat.id}")
                        v6_prefix.tags.add(nat)
                else:
                    raise AbortScript(f"Prefix is neither v4 or v6, shouldn't happend!")


            #Cheky. But let's resolve the l3 termination hardkoded instead of resolving via netbox.
            l3Term, l3Intf = getL3(self, data)
            self.log_success(f"{l3Term} - {l3Intf} - vl{vid}")  
    
            l3Uplink = Interface.objects.create(
                device=l3Term,
                description = f'C: {switch.name} - VLAN {vlan.id}',
                name=f"{l3Intf}.{vid}",
                type=InterfaceTypeChoices.TYPE_VIRTUAL,
                parent=l3Intf
            )
    
    
            self.log_success(f"Created Interface: {l3Uplink.name} on {l3Term.name}") 

            v4_uplink_addr = IPAddress.objects.create(
                address=v4_prefix.get_first_available_ip(),
            )
            v6_uplink_addr = IPAddress.objects.create(
                address=v6_prefix.get_first_available_ip(),
            )
            l3Uplink.ip_addresses.add(v4_uplink_addr)
            l3Uplink.ip_addresses.add(v6_uplink_addr)
            l3Uplink.tagged_vlans.add(vlan.id)


        mgmt_vlan_interface = Interface.objects.create(
            device=switch,
            name=f"vlan.{mgmt_vlan.vid}",
            description = f'X: Mgmt',
            type=InterfaceTypeChoices.TYPE_VIRTUAL,
            mode=InterfaceModeChoices.MODE_TAGGED,
        )

        mgmt_vlan_interface.tagged_vlans.add(mgmt_vlan.id)

        uplink_ae = Interface.objects.create(
            device=switch,
            name="ae0",
            description = f"B: {data['destination_device'].name}",
            type=InterfaceTypeChoices.TYPE_LAG,
            mode=InterfaceModeChoices.MODE_TAGGED,
        )
        uplink_ae.tagged_vlans.add(mgmt_vlan.id)
#        uplink_vlan = Interface.objects.create(
#            device=switch,
#            name="ae0.0",
#            description=data['destination_device'].name,
#            type=InterfaceTypeChoices.TYPE_VIRTUAL,
#            parent=uplink_ae,
#        )

        # Hack to create AE name
        if data['leveranse'].name == "Access Switch":
            dest_ae_id = vlan.vid
        elif data['leveranse'].name == "Distribution Switch":
            dest_ae_id = str(random.randint(5000,6000))
            self.log_warning("SCRIPT IS GENERATING AE WITH RANDOM NUMBER. PLS FIX ACCORDING TO TEMPLATE :(")

        destination_ae = Interface.objects.create(
            device=data['destination_device'],
            name=f"ae{dest_ae_id}",
            description = f'B: {switch.name}',
            type=InterfaceTypeChoices.TYPE_LAG,
            mode=InterfaceModeChoices.MODE_TAGGED,
        )
        if data['leveranse'].name == "Access Switch":        
            destination_ae.tagged_vlans.add(mgmt_vlan.id)
            destination_ae.tagged_vlans.add(vlan.id)
        self.log_success("Created AE and VLAN interfaces for both ends")

        mgmt_prefix_v4 = mgmt_vlan.prefixes.get(prefix__family=4)
        mgmt_prefix_v6 = mgmt_vlan.prefixes.get(prefix__family=6)

        v4_mgmt_addr = IPAddress.objects.create(
            address=mgmt_prefix_v4.get_first_available_ip(),
        )
        v6_mgmt_addr = IPAddress.objects.create(
            address=mgmt_prefix_v6.get_first_available_ip(),
        )
        mgmt_vlan_interface.ip_addresses.add(v4_mgmt_addr)
        mgmt_vlan_interface.ip_addresses.add(v6_mgmt_addr)
        switch.primary_ip4 = v4_mgmt_addr
        switch.primary_ip6 = v6_mgmt_addr
        switch.save()

        num_uplinks = len(data['destination_interfaces'])
        interfaces = list(Interface.objects.filter(device=switch, type=data['uplink_type']).exclude(type=InterfaceTypeChoices.TYPE_VIRTUAL).exclude(type=InterfaceTypeChoices.TYPE_LAG))
        if len(interfaces) < 1:
            raise AbortScript(f"You chose a device type without any {data['uplink_type']} interfaces! Pick another model :)")
        interface_type = ContentType.objects.get_for_model(Interface)
        for uplink_num in range(0, num_uplinks):
            # mark last ports as uplinks
            a_interface = data['destination_interfaces'][::-1][uplink_num]
            b_interface = interfaces[(uplink_num * -1) -1]

            # Fix Descriptions
            a_interface.description = f'G: {switch.name} (ae0)'
            b_interface.description = f"G: {data['destination_device'].name} (ae0)"

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

        try:
            uplink_tag = Tag.objects.get(slug=f"{num_uplinks}-uplinks")
            switch.tags.add(uplink_tag)
        except Tag.DoesNotExist as e:
            self.log_error("Failed to find device tag with {num_uplinks} uplinks.")
            raise e

        uplink_type = data['uplink_type']
        if uplink_type in [InterfaceTypeChoices.TYPE_10GE_SFP_PLUS, InterfaceTypeChoices.TYPE_10GE_FIXED]:
            uplink_type_tag = Tag.objects.get(slug="10g-uplink")
            switch.tags.add(uplink_type_tag)
            self.log_info(f"Added device tag for 10g uplinks if it wasn't present already: {uplink_type_tag}")

        self.log_success(f"To create this switch in Gondul you can <a href=\"/extras/scripts/netbox2gondul.Netbox2Gondul/?device={ switch.id }\">trigger an update immediately</a> or <a href=\"{switch.get_absolute_url()}\">view the device</a> first and trigger an update from there.")

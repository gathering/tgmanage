from django.contrib.contenttypes.models import ContentType

from dcim.choices import InterfaceModeChoices, InterfaceTypeChoices
from dcim.models import Cable, CableTermination, Device, DeviceRole, DeviceType, Interface, Site
from extras.models import Tag
from extras.scripts import *
from ipam.models import IPAddress, Prefix, VLAN, VLANGroup
from netaddr import IPNetwork


# Used for getting existing types/objects from Netbox.
ACCESS_SWITCH_DEVICE_ROLE = DeviceRole.objects.get(name='Access Switch')
DEFAULT_SITE = Site.objects.get(slug='floor')
DEFAULT_DEVICE_TYPE = DeviceType.objects.get(model='EX2200-48T')
FLOOR_MGMT_VLAN = VLAN.objects.get(name="edge-mgmt.floor.r1.tele")
VLAN_GROUP_FLOOR = VLANGroup.objects.get(slug="floor")
MULTIRATE_DEVICE_TYPE = DeviceType.objects.get(model="EX4300-48MP")
CORE_DEVICE = Device.objects.get(name="r1.tele")
CORE_INTERFACE_FLOOR = Interface.objects.get(device=CORE_DEVICE, description="d1.roof")

TG = Tag.objects.get
ACCESS_FLOOR_TAGS = [TG(slug="deltagere")]
EX2200_TAGS = [TG(slug='3-uplinks')]
MULTIRATE_TAGS = [TG(slug="multirate"), TG(slug="10g-uplink"), TG(slug="10g-copper"), TG(slug="2-uplinks")]

# Copied from examples/tg19/netbox_tools/switchestxt2netbox.py
def parse_switches_txt(switches_txt_lines):
    switches = {}
    for switch in switches_txt_lines:
        # example:
        # e7-1 88.92.80.0/26 2a06:5844:e:71::/64 88.92.0.66/26 2a06:5841:d:2::66/64 1071 s2.floor
        switch = switch.strip().split()
        if len(switch) == 0:
            # skip empty lines
            continue
        switches[switch[0]] = {
            'sysname': switch[0],
            'subnet4': switch[1],
            'subnet6': switch[2],
            'mgmt4': switch[3],
            'mgmt6': switch[4],
            'vlan_id': int(switch[5]),
            'distro_name': switch[6],
            'device_type': DEFAULT_DEVICE_TYPE,
            'lag_name': "ae0",
        }
    return switches

def parse_patchlist_txt(patchlist_txt_lines, switches):
    for patchlist in patchlist_txt_lines:
        columns = patchlist.split()
        switch_name = columns[0]
        if 'multirate' in patchlist:
            switches[switch_name]['device_type'] = MULTIRATE_DEVICE_TYPE

        uplinks = []
        links = columns[2:]
        for link in links:
            # Skip columns with comments
            if 'ge-' in link or 'mge-' in link:
                uplinks.append(link)
        switches[switch_name]['uplinks'] = uplinks


class Planning2Netbox(Script):

    class Meta:
        name = "Planning to netbox"
        description = "Import output from planning into netbox"
        commit_default = False
        field_order = ['site_name', 'switch_count', 'switch_model']
        fieldsets = ""

    switches_txt = TextVar(
        description="Switch output from planning",
    )

    patchlist_txt = TextVar(
        description="Patchlist output from planning",
    )

    def run(self, data, commit):

        planning_tag, _created = Tag.objects.get_or_create(name="from-planning")

        switches_txt_lines = data['switches_txt'].split('\n')
        # clean "file" content
        for i in range(0, len(switches_txt_lines)-1):
            switches_txt_lines[i] = switches_txt_lines[i].strip()

        patchlist_txt_lines = data['patchlist_txt'].split('\n')
        # clean "file" content
        for i in range(0, len(patchlist_txt_lines)-1):
            patchlist_txt_lines[i] = patchlist_txt_lines[i].strip()

        switches = parse_switches_txt(switches_txt_lines)
        # this modifies 'switches' 🙈
        parse_patchlist_txt(patchlist_txt_lines, switches)

        self.log_info(f"Importing {len(switches)} switches")
        for switch_name in switches:
            data = switches[switch_name]
            self.log_debug(f"Creating switch {switch_name} from {data}")
            switch, created_switch = Device.objects.get_or_create(
                name=switch_name,
                device_type=data['device_type'],
                device_role=ACCESS_SWITCH_DEVICE_ROLE,
                site=DEFAULT_SITE,
            )
            if not created_switch:
                self.log_info(f"Updating existing switch: {switch.name}")

            distro = Device.objects.get(name=data['distro_name'])
            mgmt_vlan = FLOOR_MGMT_VLAN
            ae_interface = None
            ae_interface, _created_ae_interface = Interface.objects.get_or_create(
                device=switch,
                name=f"{data['lag_name']}",
                description=distro.name,
                type=InterfaceTypeChoices.TYPE_LAG,
                mode=InterfaceModeChoices.MODE_TAGGED,
            )
            ae_interface.tagged_vlans.add(mgmt_vlan)
            
            # distro side
            distro_ae_interface, created_distro_ae_interface = Interface.objects.get_or_create(
                device=distro,
                name=f"ae{data['vlan_id']}",  # TODO: can we get this from tagged vlans  on ae?
                description=switch.name,
                type=InterfaceTypeChoices.TYPE_LAG,
                mode=InterfaceModeChoices.MODE_TAGGED,
            )
            if not created_distro_ae_interface:
                self.log_info(f"Updated existing distro interface: {distro_ae_interface}")
            distro_ae_interface.tagged_vlans.add(mgmt_vlan)

            vlan_interface, _created_vlan_interface = Interface.objects.get_or_create(
                device=switch,
                name=f"vlan.{mgmt_vlan.vid}",
                description=f"mgmt.{distro.name}",
                type=InterfaceTypeChoices.TYPE_VIRTUAL,
                mode=InterfaceModeChoices.MODE_TAGGED,
            )

            traffic_vlan, _created_traffic_vlan = VLAN.objects.get_or_create(
                name=switch.name,
                vid=data['vlan_id'],
                group=VLAN_GROUP_FLOOR,
            )

            ae_interface.tagged_vlans.add(traffic_vlan)
            ae_interface.tagged_vlans.add(traffic_vlan)

            # patchlist
            switch_uplinks = data['uplinks']

            # from planning we always cable from port 44 and upwards
            # except for multirate then we always use 47 and 48
            # 'ge-0/0/44' or 'mge-0/0/47'
            is_multirate = 'mge' in switch_uplinks[0]
            uplink_port = 46 if is_multirate else 44
            uplink_port_name = "mge-0/0/{}" if is_multirate else "ge-0/0/{}"

            interface_type = ContentType.objects.get_for_model(Interface)
            for distro_port in switch_uplinks:
                distro_interface = Interface.objects.get(
                    device=distro,
                    name=distro_port,
                )
                distro_interface.lag = distro_ae_interface
                distro_interface.save()

                switch_uplink_interface = Interface.objects.get(
                    device=switch,
                    name=uplink_port_name.format(uplink_port),
                )
                switch_uplink_interface.lag = ae_interface
                switch_uplink_interface.save()

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
                        termination_id=switch_uplink_interface.id,
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
                    termination_id=switch_uplink_interface.id,
                    termination_type=interface_type,
                )
                cable = Cable.objects.get(id=cable.id)
                # https://github.com/netbox-community/netbox/discussions/10199
                cable._terminations_modified = True
                cable.save()
                cable.tags.add(planning_tag)

                #self.log_debug(f"Cabled switch port {b} to distro port {a}")

                uplink_port += 1

            tags = ACCESS_FLOOR_TAGS.copy()
            if is_multirate:
                tags += MULTIRATE_TAGS.copy()
            else:
                tags += EX2200_TAGS.copy()
            switch.tags.add(*tags)

            # Set mgmt ip
            mgmt_addr_v4, _ = IPAddress.objects.get_or_create(
                address=data['mgmt4'],
                assigned_object_type=interface_type,
                assigned_object_id=vlan_interface.id,
            )
            mgmt_addr_v6, _ = IPAddress.objects.get_or_create(
                address=data['mgmt6'],
                assigned_object_type=interface_type,
                assigned_object_id=vlan_interface.id,
            )
            switch.primary_ip4 = mgmt_addr_v4
            switch.primary_ip6 = mgmt_addr_v6
            switch.save()

            # Set prefix
            prefix_v4, _ = Prefix.objects.get_or_create(
                prefix=data['subnet4'],
                vlan=traffic_vlan,
            )
            prefix_v6, _ = Prefix.objects.get_or_create(
                prefix=data['subnet6'],
                vlan=traffic_vlan,
            )

            core_subinterface, _ = Interface.objects.get_or_create(
                device=CORE_DEVICE,
                parent=CORE_INTERFACE_FLOOR,
                name=f"{CORE_INTERFACE_FLOOR.name}.{traffic_vlan.vid}",
                description=switch.name,
                type=InterfaceTypeChoices.TYPE_VIRTUAL,
                mode=InterfaceModeChoices.MODE_TAGGED,
            )

            # Set gw addrs

            # We "manually create" an IP address from the defined
            # network (instead of from the Prefix object)
            # because the Prefix is not persisted in the database yet,
            # and then some of the features of it doesn't work,
            # e.g. prefix.get_first_available_ip().

            subnet4 = IPNetwork(data['subnet4'])
            uplink_addr_v4_raw = subnet4[1]
            uplink_addr_v4, _ = IPAddress.objects.get_or_create(
                address=f"{uplink_addr_v4_raw}/{subnet4.prefixlen}",
            )
            subnet6 = IPNetwork(data['subnet6'])
            uplink_addr_v6_raw = subnet6[1]
            uplink_addr_v6, _ = IPAddress.objects.get_or_create(
                address=f"{uplink_addr_v6_raw}/{subnet6.prefixlen}",
            )
            core_subinterface.ip_addresses.add(uplink_addr_v4)
            core_subinterface.ip_addresses.add(uplink_addr_v6)
            core_subinterface.tagged_vlans.add(traffic_vlan)

            # Add tag to everything we created so it's easy to identify in case we
            # want to recreate
            things_we_created = [
                switch,
                ae_interface,
                distro_ae_interface,
                vlan_interface,
                traffic_vlan,
                prefix_v4,
                prefix_v6,
                mgmt_addr_v4,
                mgmt_addr_v6,
                uplink_addr_v4,
                uplink_addr_v6,
                core_subinterface,
            ]
            for thing in things_we_created:
                thing.tags.add(planning_tag)

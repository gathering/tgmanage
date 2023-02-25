import os
import pynetbox
import yaml

nb = pynetbox.api(
    'https://netbox-dev.infra.gathering.org',
    token=os.getenv('NETBOX_API_KEY'),
    threading=True,
)

koblingsplan = {}

with open('tg23-koblingsplan.yml', 'r') as f:
    koblingsplan = yaml.safe_load(f.read())

def device_from_edge(edge):
    role = edge['type']
    if role == 'Distro':
        role = 'Distribution Switch'
    if role == 'Edge':
        role = 'Access Switch'
    return {
        'name': edge['node'],
        'role': role,
        'model': edge['model'],
    }

def get_or_create_device(device):
    if (r := nb.dcim.devices.get(name=device['name'])) and r is not None:
        print(f"Found device {r.name} {r.url}")
        return r

    print(f"📱 Creating device {device['name']}")

    device_type = nb.dcim.device_types.get(model=device['model'])
    if device_type is None:
        print(f"""❌ Device type {device['model']} is missing from NetBox. Please add it manually.
                Make sure to add any templating options e.g. for interfaces so they are created automagically.""")
        exit(1)
    
    device_role = nb.dcim.device_roles.get(name=device['role'])
    if device_role is None:
        print(f"❌ Device role {device['role']} is missing from NetBox. Please add it manually.")  # This could probably be done programatically.
        exit(1)

    default_site = nb.dcim.sites.get(name='Unknown')
    r = nb.dcim.devices.create(
        name=device['name'],
        device_role=device_role.id,
        device_type=device_type.id,
        site=default_site.id,
    )
    print(f"📱 Created device {device['name']}, {r.url}. Note: It is placed in 'site=ringen' because we don't have info about which site the device is part of.")

    return r

def get_or_create_interface(device, name, description="", dot1q_mode=''):
    if (r := nb.dcim.interfaces.get(device_id=device.id, name=name)) and r is not None:
        print(f"Found interface {device.name} {r.name} {r.url}")
        return r

    print(f"🧦 Creating interface {device.name} {name}")

    interface = nb.dcim.interfaces.create(
        device=device.id,
        name=name,
        type='1000base-t',
        description=description,
        mode=dot1q_mode,
    )

    print(f"🧦 Created interface {device.name} {interface.name} {interface.url}")

    return interface

def get_or_create_cabling(cabling):
    a = cabling['a']
    b = cabling['b']
    cable_type = kobling['cable_type']
    if cable_type == 'Singlemode LC':
        cable_type = 'smf'

    print(f"🔌 Planning cable A<->B: {a['node']} {a['interface']}<->{b['interface']} {b['node']}")

    a_device_spec = device_from_edge(a)
    a_device = get_or_create_device(a_device_spec)
    a_node_description = a['node_description'] if 'node_description' in a else ''
    a_interface = get_or_create_interface(a_device, a['interface'], a_node_description)

    b_device_spec = device_from_edge(b)
    b_device = get_or_create_device(b_device_spec)
    b_node_description = b['node_description'] if 'node_description' in b else ''
    b_interface = get_or_create_interface(b_device, b['interface'], b_node_description)

    a_ae_interface = get_or_create_interface(a_device, a['ae'], dot1q_mode='tagged', description=b_device.name)
    b_ae_interface = get_or_create_interface(b_device, b['ae'], dot1q_mode='tagged', description=a_device.name)

    if (a_interface.cable and b_interface.cable) and a_interface.cable.id == b_interface.cable.id:
        print(f'🎉 Cable already exists A<->B: {a_device.name} {a_interface.name}<->{b_interface.name} {b_device.name} {a_interface.cable.url}')
        return
    elif (a_interface.cable and b_interface.cable) and a_interface.cable.id != b_interface.cable.id:
        print('A cable already exists for these interfaces and it is not the same cable.')
        print('A-side cable:\n\t', end='')
        print(f'{a_interface.cable.display} {a_interface.cable.url}')
        print('B-side cable:\n\t', end='')
        print(f'{b_interface.cable.display} {b_interface.cable.url}')
        print(f'Please manually fix in NetBox as this is not something we can fix in this script.')
        return
    elif (a_interface.cable or b_interface.cable):
        print("⚠️ A cable already exists for one of these interfaces and it is not the same cable. I'll replace it because I trust this source the most...🤠")
        if a_interface.cable:
            print('A-side cable:\n\t', end='')
            print(f'{a_interface.cable} {a_interface.cable.url}')
            print('Deleting...')
            a_interface.cable.delete()
        if b_interface.cable:
            print('B-side cable:\n\t', end='')
            print(f'{b_interface.cable} {b_interface.cable.url}')
            print('Deleting...')
            b_interface.cable.delete()

    extra_info = a['interface_description'] if 'interface_description' in a else ''

    print(f'🔌 Cabling A<->B: {a_device.name} {a_interface.name}<->{b_interface.name} {b_device.name}')
    cable = nb.dcim.cables.create(
        a_terminations = [{
             "object_id": a_interface.id,
             "object_type": "dcim.interface",
         }],
         b_terminations = [{
             "object_id": b_interface.id,
             "object_type": "dcim.interface",
         }],
         type=cable_type,
         status = 'planned',
         color = 'c0c0c0',
         label=extra_info,  # not the best place to put 'extra info', but i dont really have a better option.
     )
    print(f'🎉 Created cable: {cable.url}')

for kobling in koblingsplan:
    get_or_create_cabling(kobling)

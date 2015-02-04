#!/usr/bin/python
# -*- coding: utf-8 -*-

'''
server_dhcp.py by Jonas "j" Lindstad for The Gathering tech:server 2015

Used to configure the Juniper EX2200 edge switches with Zero Touch Protocol
License: GPLv2

Based on the work of psychomario - https://github.com/psychomario
'''


'''

TODO

 * try/catch around each incomming packet - prevents DHCP-server from crashing if it receives a malformed packet
 
'''

import socket, binascii, time, IN
from module_craft_option import craft_option # Module that crafts DHCP options
from module_lease import lease # Module that fetches data from DB and provides data for the lease
    
if not hasattr(IN,"SO_BINDTODEVICE"):
	IN.SO_BINDTODEVICE = 25  #http://stackoverflow.com/a/8437870/541038

options_raw = {} # TODO - not a nice way to do things
option_82_1 = ''
client = ''

# Length of DHCP fields in octets, and their placement in packet.
# Ref: http://4.bp.blogspot.com/-IyYoFjAC4l8/UXuo16a3sII/AAAAAAAAAXQ/b6BojbYXoXg/s1600/DHCPTitle.JPG
# 0  OP - 1
# 1  HTYPE - 1
# 2  HLEN - 1
# 3  HOPS - 1
# 4  XID - 4
# 5  SECS - 2
# 6  FLAGS - 2
# 7  CIADDR - 4
# 8  YIADDR - 4
# 9  SIADDR - 4
# 10 GIADDR - 4
# 11 CHADDR - 6
# 12 MAGIC COOKIE - 10
# 13 PADDING - 192 octets of 0's
# 14 MAGIC COOKIE - 4
# 15 OPTIONS - variable length

#############
# FUNCTIONS #
#############

# Generator for each of the dhcp fields
def split_packet(msg,slices): 
    for x in slices:
        yield msg[:x]
        msg = msg[x:]

# Splits a chunk of hex into a list of hex. (0123456789abcdef => ['01', '23', '45', '67', '89', 'ab', 'cd', 'ef'])
def chunk_hex(hex):
    return [hex[i:i+2] for i in range(0, len(hex), 2)]

# Convert hex IP to string with formated decimal IP. (0a0000ff => 10.0.0.255)
def hex_ip_to_str(hex_ip):
    return '.'.join(str(y) for y in map(lambda x: int(x, 16), chunk_hex(hex_ip))) # cast int to str for join

# formats a MAC address in the format "b827eb9a520f" to "b8:27:eb:9a:52:0f"
def format_hex_mac(hex_mac):
    return ':'.join(str(x) for x in chunk_hex(hex_mac))

# Formats a 6 byte MAC to a readable string (b'5e\x21\x00r3' => '35:65:21:00:72:33')
def six_byte_mac_to_str(mac):
    return ':'.join('%02x' % byte for byte in mac)

# b'b827eb9a520f' => 'b8:27:eb:9a:52:0f'
def prettyprint_hex_as_str(hex):
    return ':'.join('%02x' % byte for byte in binascii.unhexlify(hex))

# Parses DHCP options - raw = hex options
def parse_options(raw):
    print('[%s] --> processing DHCP options' % client)
    chunked = chunk_hex(raw)
    chunked_length = len(chunked)
    pointer = 0 # counter - next option start
    options = {} # options dataset
    
    global options_raw 
    options_raw = {} # incomming request's options
    special_options = [53, 82]

    while True:
        option = int(chunked[pointer], 16) # option ID (0 => 255)
        code = int(chunked[pointer], 16) # option code (0 => 255) # New int for options' ID with correct name. Replaces $option
        
        length = int(chunked[pointer+1], 16) # option length
        option_payload = raw[((pointer+2)*2):((pointer+length+2)*2)] # Contains the payload of the option - without option ID and length
        options_raw[code] = option_payload # copying incomming request's options, directly usable in outgoing replies
        
        asciivalue = binascii.unhexlify(option_payload) # should not contain unreadable characters
        
        if option in special_options:
            if option is 82:
                option82_raw = option_payload
                options[option] = parse_suboptions(option, option_payload)
            elif option is 53:
                # options[option] = 1 # Not adding DHCP DISCOVER to the options list, becouse it will not be used further on
                if int(chunked[pointer+2], 16) is 1:
                    print('[%s]     --> option: %s: %s' % (client, option, 'DHCP Discover (will not be used in reply)'))
                else:
                    print('[%s]     --> option: %s: %s' % (client, option, asciivalue))

        else:
            options[option] = asciivalue
            # TODO: Formating....
            try:
                if len(asciivalue) > 30:
                    print('[%s]     --> option: %s: %s' % (client, option, asciivalue[:26] + ' [...]'))
                else:
                    print('[%s]     --> option: %s: %s' % (client, option, asciivalue))
            except Exception:
                if len(asciivalue) > 30:
                    print('[%s]     --> option: %s: %s' % (client, option, prettyprint_hex_as_str(option_payload)[:26] + ' [...]'))
                else:
                    print('[%s]     --> option: %s: %s' % (client, option, prettyprint_hex_as_str(option_payload)))
                pass
            

        pointer = pointer + length + 2 # place pointer at the next options' option ID/code field
        
        if int(chunked[pointer], 16) is 255: # end of DHCP options - allways last field
            print('[%s] --> Finished processing options' % client)
            break
    return options

# Parses suboptions
def parse_suboptions(option, raw):
    print('[%s]     --> processing suboption hook for option %s' % (client, option))
    chunked = chunk_hex(raw)
    chunked_length = len(chunked)
    pointer = 0 # counter - next option start
    dataset = {}
    
    if option is 82: # Option 82 - custom shit: Setting global variable to list
        global option_82_1
        
    while True:
        length = int(chunked[pointer+1], 16) # option length in bytes
        value = raw[4:(length*2)+(4)]

        if option is 82 and int(chunked[0], 16) is 1: # Option 82 - custom shit: Putting data in list
            option_82_1 = binascii.unhexlify(value).decode()

        print('[%s]         --> suboption %s found - value: "%s"' % (client, int(chunked[0], 16), binascii.unhexlify(value).decode())) # will fail on non-ascii characters
        
        dataset[int(chunked[0], 16)] = value
        pointer = pointer + length + 2 # place pointer at the next options' option ID/code field
        if pointer not in chunked: # end of DHCP options - allways last field
            print('[%s]     --> Finished processing suboption %s' % (client, option))
            break
    return dataset

# Parses and handles DHCP DISCOVER or DHCP REQUEST
def reqparse(message):
    data=None
    dhcpfields=[1,1,1,1,4,2,2,4,4,4,4,6,10,192,4,message.rfind(b'\xff'),1]
    hexmessage=binascii.hexlify(message)
    messagesplit=[binascii.hexlify(x) for x in split_packet(message,dhcpfields)]
    
    global client
    client = prettyprint_hex_as_str(messagesplit[11])
    
    print('[%s] Parsing DHCP packet from client' % client)

    #
    # Logical checks to decide to whether respond or reject
    #
    
    # DHCP request has been forwarded by DHCP relay
    if int(messagesplit[10]) is 0:
        print('[%s] Rejecting to process DHCP packet - not forwarded by DHCP relay' % client)
        return False
    
    # Process DHCP options
    # Test data from EX2200 first boot up
    options = parse_options(b'3501013c3c4a756e697065722d6578323230302d632d3132742d3267000000000000000000000000000000000000000000000000000000000000000000000000005222012064697374726f2d746573743a67652d302f302f302e303a626f6f747374726170ff')
    # options = parse_options(messagesplit[15])
        
    # Option 82 is set in the packet
    if 82 not in options:
        print('[%s] Rejecting to process DHCP packet - DHCP option 82 not set' % client)
        return False

    # Check DHCP request type
    if messagesplit[15][:6] == b'350101':
        mode = 'dhcp_discover'
        print('[%s] --> DHCP packet type: DHCP DISCOVER' % client)
    elif messagesplit[15][:6] == b'350103':
        mode = 'dhcp_request'
        print('[%s] --> DHCP packet type: DHCP REQUEST' % client)
    else:
        print('[%s] Rejecting to process DHCP packet - option 53 not first in DHCP request' % client)
        return False
    
    #
    # Packet passes our requirements
    #
    print('[%s] --> DHCP packet contains option 82 - continues to process' % client)
    print('[%s] --> DHCP packet forwarded by relay %s' % (client, hex_ip_to_str(messagesplit[10])))
    print('[%s] --> DHCP XID/Transaction ID: %s' % (client, prettyprint_hex_as_str(messagesplit[4])))
    
    # Handle DB request - do DB lookup based on option 82
    print('[%s] --> Looking up in the DB' % (client))
    if len(option_82_1) > 0:
        (distro, phy, vlan) = option_82_1.split(':')
        print('[%s]     --> Query details: distro_name:%s, distro_phy_port:%s' % (client, distro, phy.split('.')[0]))
        
        if lease({'distro_name': distro, 'distro_phy_port': phy.split('.')[0]}).get_dict() is not False:
            lease_details = lease({'distro_name': distro, 'distro_phy_port': phy[:-2]}).get_dict()
            print('[%s]     --> Data found, switch exists in DB - ready to craft response' % client)
        else:
            print('[%s]     --> Data not found, switch does not exists in DB' % client)
            return False
    
    if mode == 'dhcp_discover':
        print('[%s] --> crafting DHCP OFFER response' % client)
        
    if mode == 'dhcp_request':
        print('[%s] --> crafting DHCP ACK response' % client)
        
        
    print('[%s]     --> XID/Transaction ID: %s' % (client, prettyprint_hex_as_str(messagesplit[4])))
    print('[%s]     --> Client IP: %s' % (client, lease_details['mgmt_addr']))
    print('[%s]     --> Next server IP: %s' % (client, address))
    print('[%s]     --> DHCP forwarder IP: %s' % (client, hex_ip_to_str(messagesplit[10])))
    print('[%s]     --> Client MAC: %s' % (client, client))
    
    data = b'\x02' # Message type - boot reply
    data += b'\x01' # Hardware type - ethernet
    data += b'\x06' # Hardware address length - 6 octets for MAC
    data += b'\x00' # Hops
    data += binascii.unhexlify(messagesplit[4]) # XID / Transaction ID
    data += b'\x00\x01' # seconds elapsed - 1 second
    data += b'\x80\x00' # BOOTP flags - broadcast (unicast: 0x0000)
    data += b'\x00'*4 # Client IP address
    data += socket.inet_aton(lease_details['mgmt_addr']) # New IP to client
    data += socket.inet_aton(address) # Next server IP address
    data += binascii.unhexlify(messagesplit[10]) # Relay agent IP - DHCP forwarder
    data += binascii.unhexlify(messagesplit[11]) # Client MAC
    data += b'\x00'*202 # Client hardware address padding (10) + Server hostname (64) + Boot file name (128)
    data += b'\x63\x82\x53\x63' # Magic cookie
    
    #
    # Craft DHCP options
    #
    print('[%s] --> Completed DHCP header structure, building DHCP options' % client)
    if mode == 'dhcp_discover':
        print('[%s]     --> Option 53: DHCP OFFER (2)' % client)
        data += craft_option(53).raw_hex(b'\x02') # Option 53 - DHCP OFFER

    if mode == 'dhcp_request':
        print('[%s]     --> Option 53: DHCP ACK (5)' % client)
        data += craft_option(53).raw_hex(b'\x05') # Option 53 - DHCP ACK
    
    data += craft_option(54).bytes(socket.inet_aton(address)) # Option 54 - DHCP server identifier
    print('[%s]     --> Option 54 (DHCP server identifier): %s' % (client, address))
    
    data += craft_option(51).raw_hex(b'\x00\x00\xff\x00') # Option 51 - Lease time left padded with "0"
    print('[%s]     --> Option 51 (Lease time): %s' % (client, '65536'))
    
    data += craft_option(1).ip(netmask) # Option 1 - Subnet mask
    print('[%s]     --> Option 1 (subnet mask): %s' % (client, netmask))
    
    data += craft_option(3).bytes(messagesplit[10]) # Option 3 - Default gateway (set to DHCP forwarders IP)
    print('[%s]     --> Option 3 (default gateway): %s' % (client, address)) # TODO - FIX BASED ON CIDR IN DB
    
    data += craft_option(150).bytes(socket.inet_aton(address)) # Option 150 - TFTP Server. Used as target for the Zero Touch Protocol
    print('[%s]     --> Option 150 (Cisco proprietary TFTP server(s)): %s' % (client, address)) # TODO - FIX BASED ON CIDR IN DB
    
    # http://www.juniper.net/documentation/en_US/junos13.2/topics/concept/software-image-and-configuration-automatic-provisioning-understanding.html
    data += craft_option(43).bytes(craft_option(0).string('/junos/' + junos_file) + craft_option(1).string('/tg15-edge/' + lease_details['hostname']) + craft_option(3).string('http')) # Option 43 - ZTP
    print('[%s]     --> Option 43 (Vendor-specific option):' % client)
    print('[%s]         --> Suboption 0: %s' % (client, '/junos/' + junos_file))
    print('[%s]         --> Suboption 1: %s' % (client, '/tg15-edge/' + lease_details['hostname']))
    print('[%s]         --> Suboption 3: %s' % (client, 'http'))
    
    # data += '\x03\x04' + option82_raw # Option 82 - with suboptions
    
    data += b'\xff'
    return data

if __name__ == "__main__":
    interface = b'eth0'
    address = '10.0.100.2'
    broadcast = '10.0.0.255'
    netmask = '255.255.255.0'
    tftp = address
    gateway = address
    leasetime = 86400 #int
    junos_file = 'jinstall-ex-2200-12.3R6.6-domestic-signed.tgz'

    # Setting up the server, and how it will communicate    
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM) # IPv4 UDP socket
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    s.setsockopt(socket.SOL_SOCKET, 25, interface)
    s.bind(('', 67))

    # Starting the whole loop
    print('Starting main loop')
    while True: #main loop
        try:
            message, addressf = s.recvfrom(8192)
            # print(message)
            if message.startswith(b'\x01'): # UDP payload is DHCP request (discover, request, release)
                if addressf[0] == '0.0.0.0':
                    print('[%s] DHCP broadcast' % client)
                    reply_to = '<broadcast>'
                else:
                    print('[%s] DHCP unicast - DHCP forwarding' % client)
                    reply_to = addressf[0]
                data=reqparse(message) # Parse the DHCP request
                if data:
                    print('[%s] --> replying to %s' % (client, reply_to))
                    # print(b'replying with UDP payload: ' + data)
                    s.sendto(data, ('<broadcast>', 68)) # Sends reply
        except KeyboardInterrupt:
            exit()

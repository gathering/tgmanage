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

 * only process if option 82 and GIADDR != '00000000' is set in discover/request
 * try/catch around each incomming packet - prevents DHCP-server from crashing if it receives a malformed packet
 OK * lease_db
 OK    * Postgres as backend
 OK    * Identifier as dict, which maps to Postgres row names. e.g. lease_db({'distro': 'a', 'port': 'b'}).get_dict()
 
'''

import socket, binascii, time, IN
from module_craft_option import craft_option
from module_lease import lease
    
if not hasattr(IN,"SO_BINDTODEVICE"):
	IN.SO_BINDTODEVICE = 25  #http://stackoverflow.com/a/8437870/541038

options_raw = {} # TODO - not a nice way to do things
option_82_dataset = False
option_82_1 = ''

class lease_db(object):
    table = {
        'x': {
            'ip': '10.0.0.100',
            'config': 'x_config.cfg'
        },
        'y': {
            'ip': '10.0.0.101',
            'config': 'y_config.cfg'
        }
    }
    
    def __init__(self, identifier):
        self.identifier = identifier
        
    def get_ip(self):
        if self.identifier in self.table:
            return self.table[self.identifier]['ip']
        else:
            print('identifier (%s) not found' % self.identifier)
            return False
            
    def get_config(self):
        if self.identifier in self.table:
            return self.table[self.identifier]['config']
        else:
            print('identifier (%s) not found' % self.identifier)
            return False
            
    def get_dict(self):
        if self.identifier in self.table:
            return self.table[self.identifier]
        else:
            print('identifier (%s) not found' % self.identifier)
            return False
    

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

# Parses DHCP options - raw = hex options
def parse_options(raw):
    print(' --> processing DHCP options')
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
                    print('     --> option: %s: %s' % (option, 'DHCP Discover (will not be used in reply)'))
                else:
                    print('     --> option: %s: %s' % (option, asciivalue))

        else:
            options[option] = asciivalue
            print('     --> option: %s: %s' % (option, asciivalue))

        pointer = pointer + length + 2 # place pointer at the next options' option ID/code field
        
        if int(chunked[pointer], 16) is 255: # end of DHCP options - allways last field
            print(' --> finished processing options')
            break
    return options

# Parses suboptions
def parse_suboptions(option, raw):
    print('     --> processing suboption hook for option %s' % option)
    chunked = chunk_hex(raw)
    chunked_length = len(chunked)
    pointer = 0 # counter - next option start
    dataset = {}
    
    if option is 82: # Option 82 - custom shit: Setting global variable to list
        global option_82_1
        # global option_82_dataset
        # option_82_dataset = []
        
    while True:
        length = int(chunked[pointer+1], 16) # option length in bytes
        value = raw[4:(length*2)+(4)]

        if option is 82 and int(chunked[0], 16) is 1: # Option 82 - custom shit: Putting data in list
            option_82_1 = binascii.unhexlify(value).decode()

        print('         --> suboption %s found - value: "%s"' % (int(chunked[0], 16), binascii.unhexlify(value).decode())) # will fail on non-ascii characters
        dataset[int(chunked[0], 16)] = value
        pointer = pointer + length + 2 # place pointer at the next options' option ID/code field
        if pointer not in chunked: # end of DHCP options - allways last field
            print('     --> finished processing suboption %s' % option)
            break
    return dataset

# Parses and handles DHCP DISCOVER or DHCP REQUEST
def reqparse(message):
    data=None
    dhcpfields=[1,1,1,1,4,2,2,4,4,4,4,6,10,192,4,message.rfind(b'\xff'),1]
    hexmessage=binascii.hexlify(message)
    messagesplit=[binascii.hexlify(x) for x in split_packet(message,dhcpfields)]
    
    # Test parsing
    options = parse_options(b'3501013c3c4a756e697065722d6578323230302d632d3132742d3267000000000000000000000000000000000000000000000000000000000000000000000000005222012064697374726f2d746573743a67652d302f302f302e303a626f6f747374726170ff')
    # options = parse_options(messagesplit[15])
    
    # print(parse_suboptions('82', options[82]))
    
    if 82 in options: # contains option 82 - was forwarded by a DHCP relay
        print(' --> DHCP packet contains option 82 -> should be processed')
        # print(options[82])
    else:
        print(' --> DHCP packet does not contain option 82 -> should be dropped')
    
    if int(messagesplit[10]) is not 0:
        print(' --> DHCP packet forwarded by relay %s' % hex_ip_to_str(messagesplit[10]))
    else:
        print(' --> DHCP packet not forwarded - direct request')
    
    # print(b'DHCP XID/Transaction ID:' + messagesplit[4])
    
    
    
    
    # Testing - do DB lookup based on option 82
    if len(option_82_1) > 0:
        # print(option_82_1)
        (distro, phy, vlan) = option_82_1.split(':')
        
        # lease.debug = True
        if lease({'distro_name': distro, 'distro_phy_port': phy.split('.')[0]}).get_dict() is not False:
            lease_details = lease({'distro_name': distro, 'distro_phy_port': phy[:-2]}).get_dict()
            print(' --> Found match in DB with distro_name:' + distro + ' distro_phy_port:' + phy.split('.')[0])
    
    if messagesplit[15][:6] == b'350101': # option 53 (should allways be the first option in DISCOVER/REQUEST) - identifies DHCP packet type - discover/request/offer/ack++
        print('\n\nDHCP DISCOVER - client MAC %s' % format_hex_mac(messagesplit[11]))
        print(' --> crafting DHCP OFFER response')
        
        # lease = getlease(messagesplit[11].decode()) # Decodes MAC address

        # DHCP OFFER details - Options
        data = b'\x02' # Message type - boot reply
        data += b'\x01' # Hardware type - ethernet
        data += b'\x06' # Hardware address length - 6 octets for MAC
        data += b'\x00' # Hops
        data += binascii.unhexlify(messagesplit[4]) # XID / Transaction ID
        data += b'\x00\x01' # seconds elapsed - 1 second
        data += b'\x80\x00' # BOOTP flags - broadcast (unicast: 0x0000)
        data += b'\x00'*4 # Client IP address
        data += socket.inet_aton(lease_details['mgmt_addr']) # New IP to client
        data += socket.inet_aton(address) # Next server IP addres - self
        data += binascii.unhexlify(messagesplit[10]) # Relay agent IP - DHCP forwarder
        data += binascii.unhexlify(messagesplit[11]) # Client MAC
        data += b'\x00'*202 # Client hardware address padding (10) + Server hostname (64) + Boot file name (128)
        data += b'\x63\x82\x53\x63' # Magic cookie
        
        # DHCP Options - ordered by pcapng "proof of concept" file
        data += craft_option(53).raw_hex(b'\x02') # Option 53 - DHCP OFFER

    elif messagesplit[15][:6] == b'350103':
        print('\n\nDHCP REQUEST - client MAC %s' % format_hex_mac(messagesplit[11]))
        print(' --> crafting DHCP ACK response')
        
        data = b'\x02' # Message type - boot reply
        data += b'\x01' # Hardware type - ethernet
        data += b'\x06' # Hardware address length - 6 octets for MAC
        data += b'\x00' # Hops
        data += binascii.unhexlify(messagesplit[4]) # XID / Transaction ID
        data += b'\x00\x01' # seconds elapsed - 1 second
        data += b'\x80\x00' # BOOTP flags - broadcast (unicast: 0x0000)
        data += b'\x00'*4 # Client IP address
        data += socket.inet_aton(lease_details['mgmt_addr']) # New IP to client <<<<<<<<<<<<<<<<<<<<<<<< ALL THE FUCKINGS IN THE WORLD
        data += socket.inet_aton(address) # Next server IP addres - self
        data += binascii.unhexlify(messagesplit[10]) # Relay agent IP - DHCP forwarder
        data += binascii.unhexlify(messagesplit[11]) # Client MAC
        data += b'\x00'*202 # Client hardware address padding (10) + Server hostname (64) + Boot file name (128)
        data += b'\x63\x82\x53\x63' # Magic cookie
        
        # DHCP Options - ordered by pcapng "proof of concept" file
        data += b'\x35\x01\05' # Option 53 - DHCP ACK
    else:
        print('Unexpected DHCP option 53 - stopping processing request')
        return None


    # common options for both DHCP REPLY and DHCP ACK - should be most of the options
    data += craft_option(54).bytes(socket.inet_aton(address)) # Option 54 - DHCP server identifier
    print('     --> Option 54 (DHCP server identifier): %s' % address)
    data += craft_option(51).raw_hex(b'\x00\x00\xff\x00') # Option 51 - Lease time left padded with "0"
    print('     --> Option 51 (Lease time): %s' % '???')
    data += craft_option(1).ip(netmask) # Option 1 - Subnet mask
    print('     --> Option 51 (Subnet mask): %s' % netmask)
    
    # Set option 3 - default gateway. Only applicable if messagesplit[10] (DHCP forwarder (GIADDR)) is set
    if messagesplit[10] == b'00000000':
        data += craft_option(3).bytes(socket.inet_aton(address)) # Option 3 - Default gateway (set to DHCP servers IP)
        print('     --> Option 3 (Default gateway): %s' % address)
    else:
        data += craft_option(3).bytes(messagesplit[10]) # Option 3 - Default gateway (set to DHCP forwarders IP)
    data += craft_option(150).bytes(socket.inet_aton(address)) # Option 150 - TFTP Server
    data += craft_option(43).bytes(craft_option(1).string('/tg15-edge/' + lease_details['hostname']) + craft_option(3).string('http')) # Option 43 - ZTP
    print('     --> Option 43 (Vendor-specific option):')
    print('         --> Suboption 1: %s' % '/tg15-edge/' + lease_details['hostname'])
    print('         --> Suboption 3: %s' % 'http')
    # data += '\x03\x04' + option82_raw # Option 82 - with suboptions
    data += b'\xff'
        
    return data

def release(): #release a lease after timelimit has expired
    for lease in leases:
       if not lease[1]:
          if time.time()+leasetime == leasetime:
              continue
          if lease[-1] > time.time()+leasetime:
             print("Released" + lease[0])
             lease[1]=False
             lease[2]='000000000000'
             lease[3]=0

def getlease(hwaddr): #return the lease of mac address, or create if doesn't exist
   global leases
   for lease in leases:
      if hwaddr == lease[2]:
         return lease[0]
   for lease in leases:
      if not lease[1]:
         lease[1]=True
         lease[2]=hwaddr
         lease[3]=time.time()
         return lease[0]

if __name__ == "__main__":
    interface = b'eth0'
    address = '10.0.100.2'
    offerfrom = '10.0.0.100'
    offerto = '10.0.0.150'
    broadcast = '10.0.0.255'
    netmask = '255.255.255.0'
    tftp = address
    dns = '8.8.8.8'
    gateway = address
    leasetime=86400 #int

    leases=[] # leases database
    #next line creates the (blank) leases table. This probably isn't necessary.
    # for ip in ['.'.join(elements_in_address[0:3])+'.'+str(x) for x in range(int(offerfrom[offerfrom.rfind('.')+1:]),int(offerto[offerto.rfind('.')+1:])+1)]:
    for octet in range(50):
        leases.append(['10.0.0.' + str(octet), False, '000000000000', 0])
    #     leases.append([ip,False,'000000000000',0])
    
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM) # IPv4 UDP socket
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    s.setsockopt(socket.SOL_SOCKET, 25, interface)
    s.bind(('', 67))

    print('starting main loop')
    while 1: #main loop
        try:
            message, addressf = s.recvfrom(8192)
            # print(message)
            if message.startswith(b'\x01'): # UDP payload is DHCP request (discover, request, release)
                if addressf[0] == '0.0.0.0':
                    print('DHCP broadcast')
                    reply_to = '<broadcast>'
                else:
                    print('DHCP unicast - DHCP forwarding')
                    reply_to = addressf[0]
                data=reqparse(message) # Parse the DHCP request
                if data:
                    print(' --> replying to %s' % reply_to)
                    # print(b'replying with UDP payload: ' + data)
                    s.sendto(data, ('<broadcast>', 68)) # Sends reply
                release() # update releases table
        except KeyboardInterrupt:
            exit()

#!/usr/bin/python
# -*- coding: utf-8 -*-

# server_dhcp.py by Jonas "j" Lindstad for The Gathering tech:server 2015
# Used to configure the Juniper EX2200 edge switches with Zero Touch Protocol
# License: GPLv2
# Copyed/influcenced by the work of psychomario - https://github.com/psychomario

import socket,binascii,time,IN
from sys import exit
from optparse import OptionParser

if not hasattr(IN,"SO_BINDTODEVICE"):
	IN.SO_BINDTODEVICE = 25  #http://stackoverflow.com/a/8437870/541038

options_raw = {}

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

def slicendice(msg,slices): #generator for each of the dhcp fields
    # slicendice(message,dhcpfields)
    for x in slices:
        # if str(type(x)) == "<type 'str'>": x=eval(x) #really dirty, deals with variable length options
        # print(x)
        # print(msg)
        yield msg[:x]
        msg = msg[x:]

# Splits a chunk of hex into a list of hex. (0123456789abcdef => ['01', '23', '45', '67', '89', 'ab', 'cd', 'ef'])
def chunk_hex(hex):
    # return [hex[i:i+2].decode('utf-8') for i in range(0, len(hex), 2)]
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
    # print(type(raw))
    # raw = '3501013c3c4a756e697065722d6578323230302d632d3132742d3267000000000000000000000000000000000000000000000000000000000000000000000000005222012064697374726f2d746573743a67652d302f302f302e303a626f6f747374726170ff'
    chunked = chunk_hex(raw)
    print(chunked)
    chunked_length = len(chunked)
    pointer = 0 # counter - next option start
    options = {} # options dataset
    global options_raw
    options_raw = {}
    special_options = [53, 82]

    while True:
        # print(chunked[pointer])
        option = int(chunked[pointer], 16) # option ID (0 => 255)
        code = int(chunked[pointer], 16) # option code (0 => 255)
        length = int(chunked[pointer+1], 16) # option length
        option_payload = raw[((pointer+2)*2):((pointer+length+2)*2)] # Contains the payload of the option - without option ID and length
        options_raw[code] = option_payload
        '''
        # converts payload to ASCII and strips spaces in both ends, and removes repeating 0000s in the end of the string.
        asciivalue = binascii.hexlify(option_payload.decode("hex").strip()).rstrip('0')
        if len(asciivalue) % 2 == 1:
            asciivalue = asciivalue + "0"
        asciivalue = binascii.unhexlify(asciivalue)
        '''
        asciivalue = binascii.unhexlify(option_payload) # should not contain unreadable characters
        # print('option_payload:')
        # print(option_payload)
        # print('asciivalue:')
        # print(asciivalue)
        
        if option in special_options:
            if option is 82:
                global option82_raw
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
            print('     --> option: %s: "%s"' % (option, asciivalue))

        pointer = pointer + length + 2 # length of option + length field (1 chunk) + option ID (1 chunk)
        if int(chunked[pointer], 16) is 255: # end of DHCP options
            print(' --> finished processing options')
            break
    return options

def parse_suboptions(option, raw):
    print('     --> processing hook for option %s' % option)
    chunked = chunk_hex(raw)
    chunked_length = len(chunked)
    dataset = {}
    if int(chunked[0], 16) is 1: # suboption 1 - loop over suboptions
        while True:
            subopt_length = int(chunked[2], 16)
            value = raw[2:(subopt_length+2)].strip()
            print('         --> suboption 1 found - value: "%s"' % value)
            dataset[int(chunked[0], 16)] = value
            break;
    return dataset

def reqparse(message): #handles either DHCPDiscover or DHCPRequest
    data=None
    # dhcp_option_length = message.rfind(b'\xff')
    # dhcpfields=[1,1,1,1,4,2,2,4,4,4,4,6,10,192,4,"msg.rfind('\xff')",1,None]
    dhcpfields=[1,1,1,1,4,2,2,4,4,4,4,6,10,192,4,message.rfind(b'\xff'),1]
    #send: boolean as to whether to send data back, and data: data to send, if any
    #print len(message)
    hexmessage=binascii.hexlify(message)
    messagesplit=[binascii.hexlify(x) for x in slicendice(message,dhcpfields)]
    print(messagesplit)
    # print(messagesplit)
    # dhcpopt=messagesplit[15][:6] # Checs first option, which should be DHCP type
    if messagesplit[15][:6] == b'350101': # option 53 - identifies DHCP packet type - discover/request/offer/ack++
        print('\n\nDHCP DISCOVER - client MAC %s' % format_hex_mac(messagesplit[11]))
        if int(messagesplit[10]) is not 0:
            print(' --> Relay: %s' % hex_ip_to_str(messagesplit[10]))
        else:
            print(' --> Relay: none - direct request')
        # options = parse_options('x')
        options = parse_options(messagesplit[15])
        # print(options)
        
        option43 = {
            'length': hex(30),
            'value': '01162f746731352d656467652f746573742e636f6e6669670304687474709'
        }
        
        #
        # Crafting DHCP OFFER
        #
        # {82: {1: 'distro-test:ge-0/0/0.0:bootstrap'}, 60: 'Juniper-ex2200-c-12t-2g', 53: 1}
        #options = \xcode \xlength \xdata
        print(' --> crafting response')
        lease=getlease(messagesplit[11].decode()) # Decodes MAC address
        # print(binascii.unhexlify(messagesplit[4]))
        # print('length: ' + str(len(binascii.unhexlify(messagesplit[4]))));
        
        # DHCP OFFER details - Options
        data = b'\x02' # Message type - boot reply
        data += b'\x01' # Hardware type - ethernet
        data += b'\x06' # Hardware address length - 6 octets for MAC
        data += b'\x00' # Hops
        data += binascii.unhexlify(messagesplit[4]) # XID / Transaction ID
        data += b'\x00\x01' # seconds elapsed - 1 second
        data += b'\x80\x00' # BOOTP flags - broadcast (unicast: 0x0000)
        data += b'\x00'*4 # Client IP address
        data += socket.inet_aton(lease) # New IP to client
        data += socket.inet_aton(address) # Next server IP addres - self
        data += binascii.unhexlify(messagesplit[10]) # Relay agent IP - DHCP forwarder
        data += binascii.unhexlify(messagesplit[11]) # Client MAC
        data += b'\x00'*202 # Client hardware address padding (10) + Server hostname (64) + Boot file name (128)
        data += b'\x63\x82\x53\x63' # Magic cookie
        
        # DHCP Options - ordered by pcapng "proof of concept" file
        data += b'\x35\x01\x02' # Option 53 - DHCP OFFER
        data += b'\x36\x04' + socket.inet_aton(address) # Option 54 - DHCP server identifier
        data += b'\x33\x04' + binascii.unhexlify(b'00012340') # Option 51 - Lease time left padded with "0"
        data += b'\x01\x04' + socket.inet_aton(netmask) # Option 1 - Subnet mask
        data += b'\x03\x04' + binascii.unhexlify(messagesplit[10]) # Option 3 - Router (set to DHCP forwarders IP)
        data += b'\x96\x04' + socket.inet_aton(address) # Option 150 - TFTP Server
        # data += '\x2b'  + option43['length'] + option43['value'] # Option 43 - Magic ZTP stuff
        # data += '\x03\x04' + option82_raw # Option 82 - with suboptions
        data += b'\xff'

    elif messagesplit[15][:6] == b'350103':
        print('\n\nDHCP REQUEST - client MAC %s' % format_hex_mac(messagesplit[11]))
        print(' --> crafting response')
        
        data = b'\x02' # Message type - boot reply
        data += b'\x01' # Hardware type - ethernet
        data += b'\x06' # Hardware address length - 6 octets for MAC
        data += b'\x00' # Hops
        data += binascii.unhexlify(messagesplit[4]) # XID / Transaction ID
        data += b'\x00\x01' # seconds elapsed - 1 second
        data += b'\x80\x00' # BOOTP flags - broadcast (unicast: 0x0000)
        data += b'\x00'*4 # Client IP address
        # data += binascii.unhexlify(messagesplit[15][messagesplit[15].find('3204')+4:messagesplit[15].find('3204')+12])
        data += binascii.unhexlify(messagesplit[8]) # New IP to client
        data += socket.inet_aton(address) # Next server IP addres - self
        data += binascii.unhexlify(messagesplit[10]) # Relay agent IP - DHCP forwarder
        data += binascii.unhexlify(messagesplit[11]) # Client MAC
        data += b'\x00'*202 # Client hardware address padding (10) + Server hostname (64) + Boot file name (128)
        data += b'\x63\x82\x53\x63' # Magic cookie
        
        # DHCP Options - ordered by pcapng "proof of concept" file
        data += b'\x35\x01\05' # Option 53 - DHCP ACK
        data += b'\x36\x04' + socket.inet_aton(address) # Option 54 - DHCP server identifier
        data += b'\x33\x04' + binascii.unhexlify(b'00012340') # Option 51 - Lease time left padded with "0"
        data += b'\x01\x04' + socket.inet_aton(netmask) # Option 1 - Subnet mask
        data += b'\x03\x04' + binascii.unhexlify(messagesplit[10]) # Option 3 - Router (set to DHCP forwarders IP)
        data += b'\x96\x04' + socket.inet_aton(address) # Option 150 - TFTP Server
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
    interface = 'eth0'
    port = 67
    address = '10.0.100.2'
    offerfrom = '10.0.0.100'
    offerto = '10.0.0.150'
    broadcast = '10.0.0.255'
    netmask = '255.255.255.0'
    tftp = address
    dns = '8.8.8.8'
    gateway = address
    pxefilename = 'pxelinux.0'
    leasetime=86400 #int

    leases=[] # leases database
    #next line creates the (blank) leases table. This probably isn't necessary.
    # for ip in ['.'.join(elements_in_address[0:3])+'.'+str(x) for x in range(int(offerfrom[offerfrom.rfind('.')+1:]),int(offerto[offerto.rfind('.')+1:])+1)]:
    for octet in range(50):
        leases.append(['10.0.0.' + str(octet), False, '000000000000', 0])
    #     leases.append([ip,False,'000000000000',0])
    
    # TODO: Support for binding to interface / IP
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM) # IPv4 UDP socket
    # python 2.7: s.setsockopt(socket.SOL_SOCKET,IN.SO_BINDTODEVICE,interface+'\0') #experimental
    # s.setsockopt(socket.SOL_SOCKET, IN.SO_BINDTODEVICE, interface+'\0') #experimental
    # s.bind(address)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    s.setsockopt(socket.SOL_SOCKET, 25, b'eth0')
    s.bind(('', 67))

    print('starting main loop')
    while 1: #main loop
        try:
            message, addressf = s.recvfrom(8192)
            print('received something!')
            print(message)
            
            if message.startswith(b'\x01'): # UDP payload is DHCP request (discover, request, release)
                if addressf[0] == '0.0.0.0':
                    print('DHCP broadcast')
                    reply_to = '<broadcast>'
                else:
                    print('DHCP unicast - DHCP forwarding')
                    reply_to = addressf[0]
                # print(message.decode('ISO-8859-1'))
                data=reqparse(message) # Parse the DHCP request
                if data:
                    # print(options_raw)
                    # data = str.encode(data)
                    print(' -- > replying to %s' % reply_to)
                    print(b'replying with UDP payload: ' + data)
                    s.sendto(data, ('<broadcast>', 68)) # Sends reply
                    # s.sendto(data,(reply_to,68)) # Sends reply
                release() #update releases table
            else:
                print('not DHCP')
        except KeyboardInterrupt:
            exit()

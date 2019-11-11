#!/usr/bin/env python

import json
import requests
import os
from requests.auth import HTTPBasicAuth
from pdns import PowerDNS

import configparser
import netaddr

config = configparser.ConfigParser()
config.read('config.ini')

# TODO read from config.ini
GONDUL_URL = 'https://gondul.tg19.gathering.org'
GONDUL_USER = 'tech'
GONDUL_PASSWORD = '<Removed>'
nameservers = ['ns1.infra.gathering.org.', 'ns2.infra.gathering.org.']


pdns = PowerDNS(config['DNS']['api_url'], config['DNS']['api_key'])

# Load all zones to later check if a zone already exist
zones = []
pdns_zones = pdns.list_zones()
for zone in pdns_zones:
    zones.append(zone['name'])

r = requests.get('{}/api/read/networks'.format(GONDUL_URL), auth=HTTPBasicAuth(GONDUL_USER, GONDUL_PASSWORD))

networks = r.json()['networks']

for network in networks:
    zone = '{}.tg19.gathering.org.'.format(network)
    if zone not in zones:
        pdns.create_zone(zone, nameservers)
        pdns.create_zone_metadata(zone, 'TSIG-ALLOW-DNSUPDATE', 'dhcp_updater')
        record = {'content': networks[network]['gw4'], 'disabled': False, 'type':'A', 'set-ptr': True}
        rrset4 = {'name': 'gw.{}'.format(zone), 'changetype': 'replace', 'type':'A', 'records': [record], 'ttl': 900}
        record = {'content': networks[network]['gw6'], 'disabled': False, 'type':'AAAA', 'set-ptr': True}
        rrset6 = {'name': 'gw.{}'.format(zone), 'changetype': 'replace', 'type':'AAAA', 'records': [record], 'ttl': 900}
        print(pdns.set_zone_records(zone, [rrset4, rrset6]))


r = requests.get('{}/api/read/switches-management'.format(GONDUL_URL), auth=HTTPBasicAuth(GONDUL_USER, GONDUL_PASSWORD))

switches = r.json()['switches']

main_zone = 'tg19.gathering.org.'

lol_rrsets = []

for switch in switches:
    rrsets = []
    zone = '{}.{}'.format(switch, main_zone)
    name = zone
    if zone not in zones:
        zone = main_zone
        name = '{}.{}'.format(switch, zone)

    if switches[switch]['mgmt_v4_addr'] is not None and switches[switch]['mgmt_v4_addr'] != '':
        record = {'content': switches[switch]['mgmt_v4_addr'], 'disabled': False, 'type':'A', 'set-ptr': True}
        rrsets.append({'name': name, 'changetype': 'replace', 'type':'A', 'records': [record], 'ttl': 900})
    if switches[switch]['mgmt_v6_addr'] is not None and switches[switch]['mgmt_v6_addr'] != '':
        record = {'content': switches[switch]['mgmt_v6_addr'], 'disabled': False, 'type':'AAAA', 'set-ptr': True}
        rrsets.append({'name': name, 'changetype': 'replace', 'type':'AAAA', 'records': [record], 'ttl': 900})
    print(pdns.set_zone_records(zone, rrsets).text)
    print(zone, rrsets)

    zone = 'tg.lol.'
    name = '{}.{}'.format(switch, zone)
    if switches[switch]['mgmt_v4_addr'] is not None and switches[switch]['mgmt_v4_addr'] != '':
        record = {'content': switches[switch]['mgmt_v4_addr'], 'disabled': False, 'type':'A'}
        lol_rrsets.append({'name': name, 'changetype': 'replace', 'type':'A', 'records': [record], 'ttl': 900})
    if switches[switch]['mgmt_v6_addr'] is not None and switches[switch]['mgmt_v6_addr'] != '':
        record = {'content': switches[switch]['mgmt_v6_addr'], 'disabled': False, 'type':'AAAA'}
        lol_rrsets.append({'name': name, 'changetype': 'replace', 'type':'AAAA', 'records': [record], 'ttl': 900})

print(lol_rrsets)
print(pdns.set_zone_records('tg.lol.', lol_rrsets).text)

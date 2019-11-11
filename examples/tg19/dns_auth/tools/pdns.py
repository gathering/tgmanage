import requests
import json
import re
import netaddr

class PowerDNS:
    def __init__(self, base_url, apikey, server = 'localhost'):
        self.base_url = base_url
        self.apikey = apikey
        self.server = server

    def _query(self, uri, method, kwargs = None):
        headers = {
            'X-API-Key': self.apikey,
            'Accept': 'application/json'
        }

        if method == "GET":
            request = requests.get(self.base_url+uri, headers=headers)
        elif method == "POST":
            request = requests.post(self.base_url+uri, headers=headers, json=kwargs)
        elif method == "PUT":
            request = requests.put(self.base_url+uri, headers=headers, json=kwargs)
        elif method == "PATCH":
            request = requests.patch(self.base_url+uri, headers=headers, json=kwargs)
        elif method == "DELETE":
            request = requests.delete(self.base_url+uri, headers=headers)

        return request

    def list_zones(self):
        return self._query("/servers/%s/zones" % (self.server), "GET").json()

    def get_zone(self, domain):
        return self._query("/servers/%s/zones/%s" % (self.server, domain), "GET").json()

    def get_zone_metadata(self, domain):
        return self._query("/servers/%s/zones/%s/metadata" % (self.server, domain), "GET").json()

    def create_zone_metadata(self, domain, kind, content):
        return self._query("/servers/%s/zones/%s/metadata" % (self.server, domain), "POST", {
            'kind': kind,
            'metadata': [content]
        })

    def create_zone(self, domain, nameservers, kind = 'Master'):
        return self._query("/servers/%s/zones" % (self.server), "POST", {
            'kind': kind,
            'nameservers': nameservers,
            'name': domain
        })

    def delete_zone(self, domain):
        return self._query("/servers/%s/zones/%s." % (self.server, domain), "DELETE")

    def set_zone_records(self, domain, rrsets):
        """
            changetype Must be REPLACE or DELETE.
            With DELETE, all existing RRs matching name and type will be deleted, incl. all comments.
            With REPLACE: when records is present, all existing RRs matching name and type will be deleted, and then new records given in records will be created.
            If no records are left, any existing comments will be deleted as well.
            When comments is present, all existing comments for the RRs matching name and type will be deleted, and then new comments given in comments will be created.
            rrsets example:
            [{
                'type': 'A',
                'name': 'mail.example.com',
                'changetype': 'delete'
            },
            {
                'type': 'MX',
                'name': 'example.com',
                'changetype': 'replace',
                'records': [{'content': '0 example.com',
                          'disabled': False,
                          'name': 'example.com',
                          'ttl': 600,
                          'type': 'MX'}],
            }]
        """
        return self._query("/servers/%s/zones/%s" % (self.server, domain), "PATCH", {
            'rrsets': rrsets
        })

    def create_netbox_device_record(self, device, zone, lol_zone = None):
        r = re.search('^([A-Za-z1-9]*)\.([A-Za-z1-9]*)$', device.name)
        if r is not None:
            device_name = r.group(1)
            zone = "{}.{}.".format(r.group(2), zone)
            lol_zone = "{}.{}.".format(r.group(2), lol_zone)
        elif re.search('^([A-Za-z1-9]*) \(([A-Za-z1-9 -\/]*)\)', device.name) is not None:
            zone = "{}.".format(zone)
            lol_zone = "{}.".format(lol_zone)
            device_name = re.search('^([A-Za-z1-9]*) \(([A-Za-z1-9 -\/]*)\)', device.name).group(1)
        else:
            zone = "{}.".format(zone)
            lol_zone = "{}.".format(lol_zone)
            device_name = device.name
        fqdn = "{}.{}".format(device_name, zone)
        lol_fqdn = "{}.{}".format(device_name, lol_zone)

        if device.primary_ip4 is not None:
            record = {'content': str(netaddr.IPNetwork(str(device.primary_ip4)).ip), 'disabled': False, 'type':'A', 'set-ptr': True}
            rrset = {'name': fqdn, 'changetype': 'replace', 'type':'A', 'records': [record], 'ttl': 900}
            print(self.set_zone_records(zone, [rrset]))
            print(rrset)
            if lol_zone is not None:
                record = {'content': str(netaddr.IPNetwork(str(device.primary_ip4)).ip), 'disabled': False, 'type':'A'}
                rrset = {'name': lol_fqdn, 'changetype': 'replace', 'type':'A', 'records': [record], 'ttl': 900}
                print(self.set_zone_records(lol_zone, [rrset]).text)

        if device.primary_ip6 is not None:
            record = {'content': str(netaddr.IPNetwork(str(device.primary_ip6)).ip), 'disabled': False, 'type':'AAAA', 'set-ptr': True}
            rrset = {'name': fqdn, 'changetype': 'replace', 'type':'AAAA', 'records': [record], 'ttl': 900}
            print(self.set_zone_records(zone, [rrset]))
            print(rrset)
            if lol_zone is not None:
                record = {'content': str(netaddr.IPNetwork(str(device.primary_ip6)).ip), 'disabled': False, 'type':'AAAA'}
                rrset = {'name': lol_fqdn, 'changetype': 'replace', 'type':'AAAA', 'records': [record], 'ttl': 900}
                print(self.set_zone_records(lol_zone, [rrset]))

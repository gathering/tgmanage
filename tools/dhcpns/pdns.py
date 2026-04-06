import requests
import ipaddress


class PowerDNS:
    def __init__(self, base_url, apikey, dryrun=False):
        self.base_url = base_url
        self.apikey = apikey
        self.dryrun = dryrun
        self._rdns_v4_zones = None
        self._rdns_v6_zones = None


    def _query(self, uri, method, kwargs={}):
        if self.dryrun:
            return None

        headers = {
            'X-API-Key': self.apikey,
            'Accept': 'application/json'
        }

        if method == "GET":
            request = requests.get(self.base_url + uri, headers=headers)
        elif method == "POST":
            request = requests.post(
                self.base_url + uri,
                headers=headers,
                json=kwargs
            )
        elif method == "PUT":
            request = requests.put(
                self.base_url + uri,
                headers=headers,
                json=kwargs
            )
        elif method == "PATCH":
            request = requests.patch(
                self.base_url + uri, headers=headers, json=kwargs
            )
        elif method == "DELETE":
            request = requests.delete(self.base_url + uri, headers=headers)

        if request.headers.get('content-type') == 'application/json':
            return request.json()
        return None


    def list_zones(self):
        if self.dryrun:
            return []
        return self._query("/servers/localhost/zones", "GET")


    def get_zone(self, domain):
        return self._query("/servers/localhost/zones/%s." % domain, "GET")


    def set_records(self, domain, rrsets):
        return self._query("/servers/localhost/zones/%s" % domain, "PATCH", {
            'rrsets': rrsets
        })


    def search(self, q, max=100, object_type="all"):
        if self.dryrun:
            return []
        return self._query(
            "/servers/localhost/search-data?q={0}&max={1}&object_type={2}".format(
                q, max, object_type), "GET")


    def get_zone_metadata(self, domain):
        return self._query("/servers/localhost/zones/%s/metadata" % (domain), "GET")


    def create_zone_metadata(self, domain, kind, content):
        return self._query("/servers/localhost/zones/%s/metadata" % (domain), "POST", {
            'kind': kind,
            'metadata': [content]
        })


    def create_zone(self, domain, nameservers, kind='Master'):
        return self._query("/servers/localhost/zones", "POST", {
            'kind': kind,
            'nameservers': nameservers,
            'name': domain
        })

    def delete_zone(self, domain):
        return self._query("/servers/localhost/zones/%s." % (domain), "DELETE")


    def get_rdns_zone_from_ip(self, ip):
        if self._rdns_v4_zones is None:
            self._rdns_v4_zones = self.search("*.in-addr.arpa", 2000, "zone")
        if self._rdns_v6_zones is None:
            self._rdns_v6_zones = self.search("*.ip6.arpa", 2000, "zone")

        address = ipaddress.ip_address(ip)
        rdns_zones = self._rdns_v4_zones if address.version == 4 else self._rdns_v6_zones

        ptr = address.reverse_pointer
        rdns_zone = None
        rdns_zone_accuracy = 30
        for zone in [sub['name'] for sub in rdns_zones]:
            test = str(ptr).split('.')
            for i in range(len(test) - 3):
                x = len(test) - i
                if '.'.join(test[-x:]) + '.' in zone and rdns_zone_accuracy > i:
                    rdns_zone = zone
                    rdns_zone_accuracy = i
                    break

        return rdns_zone

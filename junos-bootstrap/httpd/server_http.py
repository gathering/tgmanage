#!/usr/bin/python
# -*- coding: utf-8 -*-

from http.server import BaseHTTPRequestHandler, HTTPServer
from string import Template
import time
import psycopg2
import psycopg2.extras
import sys

def main():
    #
    # Settings
    #
    settings = dict(
	    db = dict(
		    user = 'bootstrap',
		    password = 'asdf',
		    dbname = 'bootstrap',
		    host = 'localhost'
	    ),
	    http = dict(
		    host = 'localhost',
		    port = 80
	    )
    )
    
    #
    # Connect to DB
    #
    try:
        connect_params = ("dbname='%s' user='%s' host='%s' password='%s'" % (settings['db']['dbname'], settings['db']['user'], settings['db']['host'], settings['db']['password']))
        conn = psycopg2.connect(connect_params)
        # cur = conn.cursor()
        cur = conn.cursor(cursor_factory=psycopg2.extras.DictCursor)
        cur.execute("""SELECT * from switches""")
        rows = cur.fetchall()
        print ("\nSwitches in DB during server_http.py startup:")
        for row in rows:
            print (" --> %s, connected to %s port %s" % (row['hostname'], row['distro_name'], row['distro_phy_port']))
	
    except (psycopg2.DatabaseError, psycopg2.OperationalError) as e:
	    print ('Error: %s' % e)
	    sys.exit(1)

    except:
        print(sys.exc_info()[0])
        sys.exit(1)

    def template_get(model):
        return open(model + '.template').read()
        
    def template_parse(template_src, hostname):
        cur.execute("SELECT * FROM switches WHERE hostname = '%s'" % hostname)
        if(cur.rowcount == 1):
            row = cur.fetchall()[0]
            print(' --> DB response ok, populating template')
            d={
                'hostname': row['hostname'],
                'distro_name': row['distro_name'],
                'distro_phy_port': row['distro_phy_port'],
                'mgmt_addr': row['mgmt_addr'],
                'mgmt_cidr': row['mgmt_cidr'],
                'mgmt_gw': row['mgmt_gw'],
                'mgmt_vlan': row['mgmt_vlan']
            }
            return Template(template_src).safe_substitute(d)
        else:
            print(' --> No hits in DB for hostname "%s", cannot continue' % hostname)
            return False

    class httpd(BaseHTTPRequestHandler):
        def do_GET(self):
            print('[%s] Incoming request: source:%s path:%s ' % (time.asctime(), self.client_address[0], self.path))
            if '/tg15-edge/' in self.path:
                hostname = self.path.split('/tg15-edge/')[1]
                if len(hostname) > 0:
                    print(' --> hostname "%s" accepted, fetching info from DB' % hostname)
                    template_parsed = template_parse(template_get('ex2200'), hostname)
                    if template_parsed:
                        print(' --> sending response to client')
                        self.send_response(200)
                        self.send_header("Content-type", "text/plain")
                        self.end_headers()
                        self.wfile.write(bytes(template_parsed, "utf-8"))
                        print(' --> success - %s bytes sent to client' % len(template_parsed))
                    else:
                        print(' --> error - template could not be populated')
                else:
                    print(' --> rejected due to missing hostname')
            else:
                print(' --> rejected due to bad path')
        # silence stderr from BaseHTTPRequestHandler
        # source: http://stackoverflow.com/questions/3389305/how-to-silent-quiet-httpserver-and-basichttprequesthandlers-stderr-output
        def log_message(self, format, *args):
            return
            
    httpd_instance = HTTPServer((settings['http']['host'], settings['http']['port']), httpd)
    print("\n[%s] Server Starts - %s:%s" % (time.asctime(), settings['http']['host'], settings['http']['port']))

    try:
        httpd_instance.serve_forever()
    except KeyboardInterrupt:
        pass

    httpd_instance.server_close()
    print("\n\n[%s] HTTP Server stopped\n" % time.asctime())

if __name__ == "__main__":
	main()

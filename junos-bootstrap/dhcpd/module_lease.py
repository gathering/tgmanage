#!/usr/bin/python
# -*- coding: utf-8 -*-

'''
    Created by Jonas 'j' Lindstad for The Gathering 2015
    License: GPLv3
    
    Class used to fetch data from the Postgres DB
    
    Usage examples:
    lease.debug = True
    x = lease({'distro_name': 'distro-test', 'distro_phy_port': 'ge-0/0/6'}).get_dict()
    print('key lookup - hostname: %s' % x['hostname'])
'''

import psycopg2
import psycopg2.extras

# settings
settings = dict(
    db = dict(
	    user = 'bootstrap',
	    password = 'asdf',
	    dbname = 'bootstrap',
	    host = 'localhost'
    )
)

# connect to Postgres DB
connect_params = ("dbname='%s' user='%s' host='%s' password='%s'" % (settings['db']['dbname'], settings['db']['user'], settings['db']['host'], settings['db']['password']))
conn = psycopg2.connect(connect_params)
cur = conn.cursor(cursor_factory=psycopg2.extras.DictCursor)

class lease(object):
    debug = False

    def __init__(self, identifiers):
        if len(identifiers) > 0: # 1 or more identifiers - we're good to go
            
            # build query string
            where_pieces = []
            for x in identifiers.items():
                where_pieces.append(str(x[0]) + " = '" + str(x[1]) + "'")
            where = ' AND '.join(where_pieces)
            select = "SELECT * FROM switches WHERE " + where + " LIMIT 1"
            
            if self.debug is True:
                print('Executing query: ' + select)
            
            cur.execute(select)
            
            rows = cur.fetchall()
            if len(rows) is 1:
                if self.debug is True:
                    print('returned from DB:')
                    for key, value in rows[0].items():
                        print('%s: %s' % (key, value))
                    
                self.row = rows[0]
            else:
                self.row = False
        else:
            print('Missing identifier parameter')
            exit()
        
    def get_ip(self):
        if self.row is not False:
            return self.row['ip']
        else:
            print('identifiers (%s) not found' % self.row)
            return False
            
    def get_config(self):
        if self.row is not False:
            return self.row['config']
        else:
            print('identifiers (%s) not found' % self.row)
            return False
            
    def get_dict(self):
        if self.row is not False:
            return self.row
        else:
            print('identifiers (%s) not found' % self.row)
            return False

#! /usr/bin/perl
use strict;
use warnings;
use DBI;
package nms::config;

# Make a duplicate of this file, and save as 'config.local.pm'

our $db_name = "nms";
our $db_host = "flexus.tg13.gathering.org";
our $db_username = "nms";
our $db_password = "<removed>";

our $dhcp_server1 = "151.216.126.2";
our $dhcp_server2 = "151.216.125.17"; # Cisco ISE profiling

our $ios_user = "nms";
our $ios_pass = "<removed>";

# Tech:Net sets up at least a read-community for SNMP for use
# with dlink1g, nms and sosuch. This is the one:
our $snmp_community = "<removed>";

our $dlink1g_user = 'dlinkng';
our $dlink1g_passwd = '<removed>';

# No longer in use as of '12 ?
# our $telegw_ip = "12.34.56.78";
# our @telegw_wanlinks = ("gig1/1", "gig1/2");

our $tgname    = "tg13";

our $pri_hostname     = "winix";
our $pri_v4   = "151.216.126.2";
our $pri_v6    = "2a02:ed02:126::2";
our $pri_net   = "151.216.126.0/24";
our $sec_hostname     = "tress90";
our $sec_ptr   = "151.216.125.2";
our $sec_v6    = "2a02:ed02:125::2";

# for RIPE to get reverse zones via DNS AXFR
our $ext_xfer  = "193.0.0.0/22";
our $ext_ns    = "194.19.3.20";

# To generate new dnssec-key for ddns:
# dnssec-keygen -a HMAC-MD5 -b 128 -n HOST DHCP_UPDATER
our $ddns_key = "<removed>";
our $ddns_to  = "127.0.0.1";

# Used by make-named.pl
our $noc_nett  = "151.216.124.0/24";
our $noc_nett_v6 = "2a02:ed02:124::/64";

# Ikke i bruk i '11 til revers-soner.
# Ikke i bruk i '12 heller
# På tide å fjerne dette i '13?
# Ikke brukt i '13 heller
# På tide å fjerne dette i '14????????? :-D :-P
#our $root_arpa = "22.89.in-addr.arpa";
#our $ipv6nett = "2001:8c0:9840::/48";

our $base_ipv4net = "151.216.0.0";
our $base_ipv4prefix = 17;

our $base_ipv6net = "2a02:ed02:";
our $base_ipv6prefix = 32;
our $ipv6zone = "2.0.d.e.2.0.a.2.ip6.arpa";

our $pxe_server = "151.216.125.3";
our $ciscowlc_a = "151.216.127.15";


# static_switches is supposed to be legacy, and should be safe to remove.
#130, 144, 145, 196, 197, 198, 199, 200, 203, 201, 206, 208, 209, 211, 213,
#our @static_switches = (
#	130,144,145,190,200,201,203,206,208,209,210,211,213,215,216,217,218,219,220,221,223,250,252
#        );
#our @static_nets = (
#                  0, 212, 254, 255
#        );

# Used by ipv6-stats, but never got updated for tg11-ip's. Commenting.
# The following is the list of routing netboxes (core, dist, tele, a.s.o)
our @distrobox_ips = (
	'151.216.127.17', # distro0
	'151.216.127.18', # distro1
	'151.216.127.19', # distro2
	'151.216.127.20', # distro3
	'151.216.127.21', # distro4
	'151.216.127.9',  # crewgw
	'151.216.127.11', # gamegw
	'151.216.124.1',  # nocgw
	'151.216.127.6',  # logistikkgw
	'151.216.127.5',  # wtfgw
);

# Forwarding zones.
our @forwarding_zones = qw( );

1;

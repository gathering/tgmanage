#! /usr/bin/perl
use strict;
use warnings;
use DBI;
package nms::config;

# Don't change this file for your local setup; use config.local.pm instead.

our $db_name = "<removed>";
our $db_host = "nms.tg08.gathering.org";
our $db_username = "<removed>";
our $db_password = "<removed>";

our $zyxel_password = "<removed>";
our $telnet_timeout = 300;

# Tech:Net sets up at least a read-community for SNMP for use
our $ios_user = "<removed>";
our $ios_pass = "<removed>";

# No longer in use as of '12 ?
#our $telegw_ip = "12.34.56.78";
#our @telegw_wanlinks = ("gig1/1", "gig1/2");

1;

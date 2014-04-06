#! /usr/bin/perl
use strict;
use warnings;
require './access_list.pl';
require './nets.pl';
require './mbd.pm';

my @ports = mbd::find_all_ports();

print "no ip forward-protocol udp 137\n";
print "no ip forward-protocol udp 138\n";

for my $port (@ports) {
	print "ip forward-protocol udp $port\n";
}

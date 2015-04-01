#!/usr/bin/perl
use strict;

BEGIN {
        require "include/config.pm";
}

use Net::IP;
use NetAddr::IP;
use Getopt::Long;

my ($delete);

if (@ARGV > 0) {
        GetOptions(
        'del|delete'            => \$delete,
        )
}

# Use this to generate nsupdate for all edge switches
# Expects joined input from switches.txt and patchlist.txt
## paste -d' ' switches.txt <(cut -d' ' -f3- patchlist.txt) > working-area/switches-patchlist.txt

print "server $nms::config::pri_v4\n";

while (<STDIN>){
	# e73-4 151.216.160.64/26 2a02:ed02:160b::/64 151.216.181.141/26 2a02:ed02:181c::141/64 1734 distro6 @ports
	my ( $swname, $client_v4, $client_v6, $sw_v4, $sw_v6, $vlan, $distro, @ports ) = split;
	
	(my $v4gw = NetAddr::IP->new($client_v4)->first()) =~ s/\/[0-9]{1,2}//;
	(my $v6gw = NetAddr::IP->new($client_v6)->first()) =~ s/\/[0-9]{1,2}//;
	
	(my $v4mgmt = $sw_v4) =~ s/\/[0-9]{1,2}//;
	(my $v6mgmt = $sw_v6) =~ s/\/[0-9]{1,2}//;
	
	my $fqdn = $swname . "." . $nms::config::tgname . ".gathering.org.";
	my $sw_fqdn = "sw." . $fqdn;
	my $gw_fqdn = "gw." . $fqdn;
	my $text_info = $distro . ", vlan $vlan, " . join(' + ', @ports);
	
	# A and AAAA-record to the switch
	if($delete){
		print "update delete $sw_fqdn \t IN A\n";
		print "update delete $sw_fqdn \t IN AAAA\n";
	} else {
		print "update add $sw_fqdn \t 3600 IN A \t $v4mgmt\n";
		print "update add $sw_fqdn \t 3600 IN AAAA \t $v6mgmt\n";
	}
	print "send\n";

	# PTR to the switch
	if($delete){
		print "update delete " . Net::IP->new($v4mgmt)->reverse_ip() . " \t IN PTR\n";
		print "send\n";
		print "update delete " . Net::IP->new($v6mgmt)->reverse_ip() . " \t IN PTR\n";
	} else {
		print "update add " . Net::IP->new($v4mgmt)->reverse_ip() . " \t 3600 IN PTR \t $sw_fqdn\n";
		print "send\n";
		print "update add " . Net::IP->new($v6mgmt)->reverse_ip() . " \t 3600 IN PTR \t $sw_fqdn\n";
	}
	print "send\n";

	# TXT-record with details
	if($delete){
		print "update delete $sw_fqdn \t IN TXT\n";
	} else {
		print "update add $sw_fqdn \t 3600 IN TXT \t \"" . $text_info . "\"\n";
	}
	print "send\n";

	# A and AAAA-record to the gateway/router
	if($delete){
		print "update delete $gw_fqdn \t IN A\n";
		print "update delete $gw_fqdn \t IN AAAA\n";
	} else {
	        print "update add $gw_fqdn \t 3600 IN A \t $v4gw\n";
	        print "update add $gw_fqdn \t 3600 IN AAAA \t $v6gw\n";
	}
	print "send\n";

	# PTR to the gateway/router
	if($delete){
		print "update delete " . Net::IP->new($v4gw)->reverse_ip() . " \t IN PTR\n";
		print "send\n";
		print "update delete " . Net::IP->new($v6gw)->reverse_ip() . " \t IN PTR\n";
	} else {
	        print "update add " . Net::IP->new($v4gw)->reverse_ip() . " \t 3600 IN PTR \t $gw_fqdn\n";
		print "send\n";
	        print "update add " . Net::IP->new($v6gw)->reverse_ip() . " \t 3600 IN PTR \t $gw_fqdn\n";
	}
        print "send\n";
}

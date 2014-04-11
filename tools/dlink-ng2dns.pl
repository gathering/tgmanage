#!/usr/bin/perl
use strict;

BEGIN {
        require "include/config.pm";
        eval {
                require "include/config.local.pm";
        };
}

use Net::IP;
use Getopt::Long;

my ($delete);

if (@ARGV > 0) {
        GetOptions(
        'del|delete'            => \$delete,
        )
}

print "server $nms::config::pri_v4\n";

while (<STDIN>)
{
	my ( $sysname, $distro, $ponum, $cidr, $ipaddr, $gwaddr, $v6addr, @ports ) = split;
	
	
	my $ip = new Net::IP($ipaddr);

	my $v4gw = new Net::IP($gwaddr);

	( my $gw6 = $v6addr ) =~ s/\/.*//;
	my $v6gw = new Net::IP($gw6);

	my $fqdn = $sysname . "." . $nms::config::tgname . ".gathering.org.";
	my $sw_fqdn = $sysname . "-sw." . $fqdn;
	my $text_info = $distro . " - " . join(' + ', @ports) . ", po" . $ponum . ", gwaddr " . $gwaddr;

	# A-record to the switch
	print "prereq nxdomain " . $sw_fqdn . "\n" unless $delete;
	print "update add " . $sw_fqdn . " \t 3600 IN A \t " . $ipaddr . "\n" unless $delete;
	print "update delete " . $sw_fqdn . " \t IN A\n" if $delete;
	print "send\n";

	# PTR to the switch
	print "prereq nxdomain " . $ip->reverse_ip() . "\n" unless $delete;
	print "update add " . $ip->reverse_ip() . " \t 3600 IN PTR \t " . $sw_fqdn . "\n" unless $delete;
	print "update delete " . $ip->reverse_ip() . " \t IN PTR\n" if $delete;
	print "send\n";

	# TXT-record with details
	print "update delete " . $sw_fqdn . " IN TXT\n" unless $delete;
	print "update add " . $sw_fqdn . " \t 3600 IN TXT \t \"" . $text_info . "\"\n" unless $delete;
	print "update delete " . $sw_fqdn . " \t IN TXT\n" if $delete;
	print "send\n";

	# A and AAAA-record to the gateway/router
	print "prereq nxrrset gw." . $fqdn . " IN A\n" unless $delete;
        print "update add gw." . $fqdn . " \t 3600 IN A \t " . $gwaddr . "\n" unless $delete;
	print "update delete gw." . $fqdn . " \t IN A\n" if $delete;
        print "send\n";
	print "prereq nxrrset gw." . $fqdn . " IN AAAA\n" unless $delete;
        print "update add gw." . $fqdn . " \t 3600 IN AAAA \t " . $gw6 . "\n" unless $delete;
	print "update delete gw." . $fqdn . " \t IN AAAA\n" if $delete;
        print "send\n";

	# PTR to the gateway/router
	print "prereq nxdomain " . $v4gw->reverse_ip() . "\n" unless $delete;
        print "update add " . $v4gw->reverse_ip() . " \t 3600 IN PTR \t gw." . $fqdn . "\n" unless $delete;
	print "update delete " . $v4gw->reverse_ip() . " \t IN PTR\n" if $delete;
        print "send\n";
	print "prereq nxdomain " . $v6gw->reverse_ip() . "\n" unless $delete;
        print "update add " . $v6gw->reverse_ip() . " \t 3600 IN PTR \t gw." . $fqdn . "\n" unless $delete;
	print "update delete " . $v6gw->reverse_ip() . " \t IN PTR\n" if $delete;
        print "send\n";
}

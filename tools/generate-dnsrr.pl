#!/usr/bin/perl -I /root/tgmanage
#
# USAGE:
#  Generate BIND Zone-file data based on the file hosts-to-add.txt
#  cat hosts-to-add.txt | tools/generate-dnsrr.pl 
#
#  Generate input data for nsupdate, to add FORWARD records based on hosts-to-add.txt
#  cat hosts-to-add.txt | tools/generate-dnsrr.pl --domain foo.tgXX.gathering.org -ns
#  
#  Generate input data for nsupdate, to add REVERSE records based on hosts-to-add.txt
#  cat hosts-to-add.txt | tools/generate-dnsrr.pl --domain foo.tgXX.gathering.org -ns -rev
#
#  Generate input data for nsupdate, to DELETE forward records based on hosts-to-add.txt
#  cat hosts-to-DELETE.txt | tools/generate-dnsrr.pl --domain foo.tgXX.gathering.org -ns -del
#  
#  Generate input data for nsupdate, to DELETE reverse records based on hosts-to-add.txt
#  cat hosts-to-DELETE.txt | tools/generate-dnsrr.pl --domain foo.tgXX.gathering.org -ns -rev -del
# 
#  Command-syntax to send this to nsupdate, running it on the DNS server:
#  cat file.txt | tools/generate-dnsrr.pl --dom foo -ns | ssh $dnsserver "nsupdate -k /etc/bind/Kdhcp_updater.+157+XXXXX"
#
# Format of input:
# hostname  ipv4-adress ipv6-address
#  If any of ipv4-address or ipv6-address are NOT set for the host, specify "nope"
#  Lines starting with # will (should) be skipped (comments)
#
# Example:
#
# host1  192.168.0.1 2001:db8:f00::1
# host2  nope        2001:db8:f00::2
# host3  192.168.0.3 nope
# # comment, to be ignored.
# host4  192.168.0.4

use strict;
use warnings;
use lib '..';
BEGIN {
        require "include/config.pm";
        eval {
                require "include/config.local.pm";
        };
}
use Net::IP;
use Getopt::Long;

my ($delete, $auto, $nsupdate, $reverse, $domain);

if (@ARGV > 0) {
	GetOptions(
	'del|delete'		=> \$delete,
	'a|auto'		=> \$auto,
	'ns|nsupdate'		=> \$nsupdate,
	'r|reverse'		=> \$reverse,
	'domain=s'		=> \$domain
	)
}

if ($nsupdate || $reverse){
	unless (defined($domain)){
		print "Missing domain.\n";
		exit 1 unless defined($domain);
	}
}

$domain = "." . $domain if defined($domain);

print "server $nms::config::pri_v4\n" if ($nsupdate || $reverse);

while (<STDIN>) {
	next if /^(#|\s+$)/;	# skip if comment, or blank line

	my ($hostname, $ipv4, $ipv6) = split;
	$hostname = lc($hostname);
	
	unless ($ipv6){
		if ($auto){
			# Get IPv6-address based on IPv4-address
		
			my ($first, $second, $third, $fourth) = split('\.', $ipv4);
			# TODO: Need to do some more logic, since base_ipv6net looks like '2a02:ed02::/32'
			#$ipv6 = $nms::config::base_ipv6net . $third . "::" . $fourth;
		}
	}
	
	if ($reverse){
		# print ptr
		print_ptr($hostname, $ipv4, $ipv6);
	} else {
		# print forward
		print_fwd($hostname, $ipv4, $ipv6);
	}
}

sub print_ptr{
	my ($hostname, $ipv4, $ipv6) = @_;

	# IPv4
	unless ( $ipv4 eq "nope" ) {
		my $v4 = new Net::IP($ipv4);
		
		print "prereq nxdomain " . $v4->reverse_ip() . "\n" unless $delete;
		print "update add " . $v4->reverse_ip() . " 3600 IN PTR " . $hostname . $domain .".\n" unless $delete;
		print "update delete "  . $v4->reverse_ip() . " IN PTR\n" if $delete;
		print "send\n";
	}	

	# IPv6
	if (( not ($ipv6 eq "nope") ) && ( $ipv6 )) {
		my $v6 = new Net::IP($ipv6);
		
		print "prereq nxdomain " . $v6->reverse_ip() . "\n" unless $delete;
		print "update add " . $v6->reverse_ip() . " 3600 IN PTR " . $hostname . $domain . ".\n" unless $delete;
		print "update delete " . $v6->reverse_ip() . " IN PTR\n" if $delete;
		print "send\n";
	}
}

sub print_fwd{
	my ($hostname, $ipv4, $ipv6) = @_;
	
	if ($nsupdate){

		unless ( $ipv4 eq "nope" ) {
			# IPv4
			print "prereq nxrrset " . $hostname . $domain . " IN A\n" unless $delete;
			print "update add " . $hostname . $domain . " 3600 IN A $ipv4\n" unless $delete;
			print "update delete " . $hostname . $domain . " IN A\n" if $delete;
			print "send\n";
		}
		if (( not ($ipv6 eq "nope") ) && ( $ipv6 )) {
			# IPv6
			print "prereq nxrrset " . $hostname . $domain . " IN AAAA\n" unless $delete;
                	print "update add " . $hostname . $domain . " 3600 IN AAAA $ipv6\n" unless $delete;
	                print "update delete " . $hostname . $domain . " IN AAAA\n" if $delete;
        	        print "send\n";
		}
	} else {
		# IPv4
		unless ( $ipv4 eq "nope" ) {
			printf ("%-24s%s\t%s\t%s\n", $hostname, "IN", "A", $ipv4);
		}
		# IPv6
		if (( not ($ipv6 eq "nope") ) && ( $ipv6 )) {
			printf ("%-24s%s\t%s\t%s\n", $hostname, "IN", "AAAA", $ipv6) if ($ipv6);
		}
	}
}

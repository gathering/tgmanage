#!/usr/bin/perl
use NetAddr::IP;
use Net::IP;
#
# Input file format:
#
# ipv4-link-network router1 router2
#
# e.g.
# 151.216.0.2  telegw nocgw
# 151.216.0.4  telegw cam
# 151.216.0.6  nocgw coren
# 151.216.0.8  telegw pressegw
#
# Note: IPv6 linknets use link-local adresses, so they are not included in list.
#
while (<STDIN>) {
        next if /^(#|\s+$)/;    # skip if comment, or blank line
	
	my ($ipv4_raw, $from, $to) = split;
	my $ipv4;
	
	# Assumes ipv4 address is the first address in a /31 :-)) 
	$ipv4 = NetAddr::IP->new($ipv4_raw."/31") unless $ipv4=~/no/;
	printf STDERR "Missing IPv4 scope for linket %s -> %s\n", $from, $to if not $ipv4;
	next if not $ipv4;

	
	# generate-dnsrr.pl format:
	# hostname ipv4 ipv6 (with nope as valid null argument)
	my $ipv4_other =  $ipv4 +1;
	printf("%s-%s %s nope\n", $from, $to, $ipv4->addr); 
	printf("%s-%s %s nope\n", $to, $from, $ipv4_other->addr); 
}

#!/usr/bin/perl
use NetAddr::IP;
use Net::IP;
#
# Input file format:
#
# <ipv4-linknet> <ipv6-linknet> src-router dst-router
#
# e.g.
# 151.216.128.0/31 2a02:ed02:FFFE::0/127 rs1.tele rs1.core
# 151.216.128.2/31 2a02:ed02:FFFE::2/127 rs1.tele rs1.noc

while (<STDIN>) {
        next if /^(#|\s+$)/;    # skip if comment, or blank line
	
	my ($ipv4_raw, $ipv6_raw, $from, $to) = split;
		
	# v4 
	my $ipv4_first = NetAddr::IP->new($ipv4_raw);
	my $ipv4_second = $ipv4_first + 1;
	
	# v6
	my $ipv6_first = NetAddr::IP->new($ipv6_raw);
	my $ipv6_second = $ipv6_first + 1;

	# generate-dnsrr.pl format:
	# hostname ipv4 ipv6
	printf("%s-%s %s %s\n", $from, $to, $ipv4_first->addr, $ipv6_first->addr); 
	printf("%s-%s %s %s\n", $to, $from, $ipv4_second->addr, $ipv6_second->addr); 
}

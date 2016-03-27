#!/usr/bin/perl
use NetAddr::IP;
use Net::IP;
use Getopt::Long;

my ($first);

if (@ARGV > 0) {
        GetOptions(
        'f|first'            => \$first,
        )
}

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
		
	my ($ipv4_first, $ipv4_second, $ipv6_first, $ipv6_second);
	if($ipv6_raw =~ m/nope/){
		$ipv6_first = "nope";
		$ipv6_second = "nope";
	} else {
		my $ipv6 = NetAddr::IP->new($ipv6_raw);
		$ipv6_first = $ipv6->addr();
		$ipv6++;
		$ipv6_second = $ipv6->addr();
	}

	if($ipv4_raw =~ m/nope/){
		$ipv4_first = "";
                $ipv4_second = "";
	} else {
		my $ipv4 = NetAddr::IP->new($ipv4_raw);
		$ipv4_first = $ipv4->addr();
		$ipv4++;
		$ipv4_second = $ipv4->addr;
	}


	# generate-dnsrr.pl format:
	# hostname ipv4 ipv6
	if($first){
		printf("%s %s %s\n", $from, $ipv4_first, $ipv6_first);
		printf("%s %s %s\n", $to, $ipv4_second, $ipv6_second);
	} else {
		printf("%s-%s %s %s\n", $from, $to, $ipv4_first, $ipv6_first);
		printf("%s-%s %s %s\n", $to, $from, $ipv4_second, $ipv6_second);
	}
}

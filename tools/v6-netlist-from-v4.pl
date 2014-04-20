#! /usr/bin/perl
use strict;
use warnings;

while (<>) {
	chomp;
	/^#/ and next;
	/^(151\.216\.(\d+)\.(\d+)) (\d+) (\S+)$/ or die;
	my $z;
	my ($ip, $third, $fourth, $len, $name) = ($1, $2, $3, $4, $5);
	if ($len == 24) {
		$z = '2a02:ed02:' . $third . '::/64';
	} elsif ($len == 25) {
		if ($fourth == 0) {
			$z = '2a02:ed02:' . $third . 'a::/64';
		} else {
			$z = '2a02:ed02:' . $third . 'b::/64';
		}
	} elsif ($len == 26) {
		if ($fourth == 0) {
			$z = '2a02:ed02:' . $third . 'a::/64';
		} elsif ($fourth == 64) {
			$z = '2a02:ed02:' . $third . 'b::/64';
		} elsif ($fourth == 128) {
			$z = '2a02:ed02:' . $third . 'c::/64';
		} else {
			$z = '2a02:ed02:' . $third . 'd::/64';
		}
	} else {
		warn "Unknown len $ip/$len";
	}
	print "$z $name\n" if (defined($z));
}

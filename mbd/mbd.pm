#! /usr/bin/perl
use strict;
use warnings;
use Socket;
use Net::CIDR;
use Net::RawIP;
require './access_list.pl';
require './nets.pl';

package mbd;

sub expand_range {
	my $range = shift;

	if ($range =~ /^(\d+)\.\.(\d+)$/) {
		return $1..$2;
	} else {
		return $range;
	}
}

sub match_ranges {
	my ($elem, $ranges) = @_;
	
	for my $range (@$ranges) {
		if ($range =~ /^(\d+)\.\.(\d+)$/) {
			return 1 if ($elem >= $1 && $elem <= $2);
		} else {
			return 1 if ($elem == $range);
		}
	}

	return 0;
}

sub find_all_ports {
	# Find what ports we need to listen on
	my %port_hash = ();
	for my $e (@Config::access_list) {
		for my $r (@{$e->{'ports'}}) {
			for my $p (expand_range($r)) {
				$port_hash{$p} = 1;
			}
		}
	}
	my @ports = sort { $a <=> $b } keys %port_hash;
	return @ports;
}

1;

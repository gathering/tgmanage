#!/usr/bin/perl -I /root/tgmanage/
use strict;
use warnings;
use lib '..';
BEGIN {
        require "include/config.pm";
        eval {
                require "include/config.local.pm";
        };
}

unless (@ARGV > 0) {
	print "No arguments. Need switches.txt and patchlist.txt.\n";
	exit 1;
}

my $s = open(SWITCHES, "$ARGV[0]") or die ("Cannot open switches.txt");
my $p = open(PATCH, "$ARGV[1]") or die ("Cannot open patchlist.txt");

my $portchannel_start = 10;
my %portchannels;
my $letter = "a";

my %switches;
while(<SWITCHES>) {
	chomp;
	my ($network, $netmask, $switchname, $mngmt_ip) = split; # $mngmt_ip is unused
	$switches{$switchname} = {
		network => $network,
		netmask => $netmask,
	};
}
while (<PATCH>) {
	chomp;
	my ($switchname, $coregw, @ports) = split;
	my $network = $switches{$switchname}{network};
	my $netmask = $switches{$switchname}{netmask};
	my ($o1, $o2, $o3, $o4) = split(/\./, $network);
	
	# TG13-fiks
	# Distroene ble kalt 1-5, men planning-forvirring førte til renaming 0-4
	$coregw =~ s/^(distro)([0-9])$/$1 . ($2-1)/e;
	
	# portchannel per distro
	$portchannels{$coregw} = $portchannel_start unless ($portchannels{$coregw} && defined($portchannels{$coregw}));
	
	if ($o4 eq "0") {
                $letter = "a";
        } elsif ($o4 eq "64") {
                $letter = "b";
        } elsif ($o4 eq "128") {
                $letter = "c";
        } elsif ($o4 eq "192") {
                $letter = "d";
        }

	my $v6addr = $nms::config::base_ipv6net . $o3 . $letter ."::1/64";

	$o4 += 1;
	my $gateway_addr = "$o1.$o2.$o3.$o4";
	$o4 += 1;
	my $switch_addr = "$o1.$o2.$o3.$o4";

	print "$switchname $coregw $portchannels{$coregw} $network/$netmask $switch_addr $gateway_addr $v6addr " . join(' ', @ports) . "\n";

	# increase portchannel
	$portchannels{$coregw}++;

	die("NO MORE ETHERCHANNELS!") if($portchannels{$coregw} > 64); # IOS-XE 4500 only supports 64 portchannels
}
#! /usr/bin/perl
use strict;
use warnings;

while (<>) {
	my @arr = split " ";
	my $ap = 'ap-'.$arr[0];
	my $core = $arr[1];
	# Trekk fra 1
	$core =~ s/^(distro)(\d+)$/$1.($2-1)/e;

	# Fjerde kabel er aksesspunkt
	my $blade;
	my $port;
	if ($arr[5] =~ /^Gi(\d+)\/(\d+)$/) {
		$blade = $1;
		$port = $2;
	} else {
		die "Unknown port: ".$arr[5];
	}
	printf "INSERT INTO switches(ip, sysname, switchtype) values(inet '127.0.0.1', '%s', 'ciscoap');\n", $ap;
	printf "INSERT INTO uplinks SELECT (SELECT switch FROM switches WHERE sysname = '%s') AS switch, (SELECT switch FROM switches WHERE sysname = '%s') AS coreswitch, %d AS blade, %d AS port;\n", $ap, $core, $blade, $port;
	printf "INSERT INTO ap_poll(switch) SELECT switch FROM switches WHERE sysname = '%s';\n", $ap;
}

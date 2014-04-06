#! /usr/bin/perl
use DBI;
use POSIX;
use lib '../include';
use nms;
use strict;
use warnings;

BEGIN {
        require "../include/config.pm";
        eval {
                require "../include/config.local.pm";
        };
}

my $year = $nms::config::tgname;
$year =~ s/tg/20/; # hihi

my %months = (
	Jan => 1,
	Feb => 2,
	Mar => 3,
	Apr => 4,
	May => 5,
	Jun => 6,
	Jul => 7,
	Aug => 8,
	Sep => 9,
	Oct => 10,
	Nov => 11,
	Dec => 12
);

my ($dbh, $q, $cq);
open(SYSLOG, "tail -n 9999999 -F /var/log/syslog |") or die "Unable to tail syslog: $!";
while (<SYSLOG>) {
	/(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+(\d+)\s+(\d+:\d+:\d+).*DHCPACK on (\d+\.\d+\.\d+\.\d+) to (\S+)/ or next;
	my $date = $year . "-" . $months{$1} . "-" . $2 . " " . $3;
	my $machine = $5;
	my $owner_color;

	if ($machine eq '00:15:c5:42:ce:e9') {
		$owner_color = '#00ff00';  # Steinar
	} elsif ($machine eq '00:1e:37:1c:d2:65') {
		$owner_color = '#c0ffee';  # Trygve
	} elsif ($machine eq '00:16:d3:ce:8f:a7') {
		$owner_color = '#f00f00';  # Jon
	} elsif ($machine eq '00:16:d4:0c:8a:1c') {
		$owner_color = '#ff99ff';  # Jørgen
	} elsif ($machine eq '00:18:8b:aa:2f:f8') {
		$owner_color = '#663300';  # Kjetil
	} elsif ($machine eq '00:15:58:29:14:e3') {
		$owner_color = '#f1720f';  # Bård
	} else {
		$owner_color = "#000000";  # Unknown
	}

	if (!defined($dbh) || !$dbh->ping) {
		$dbh = nms::db_connect();
		$q = $dbh->prepare("UPDATE dhcp SET last_ack=? WHERE ?::inet << network AND ( last_ack < ? OR last_ack IS NULL )")
			or die "Couldn't prepare query";
		$cq = $dbh->prepare("UPDATE dhcp SET owner_color=? WHERE ?::inet << network AND owner_color IS NULL")
			or die "Couldn't prepare query";
	}

	print STDERR "$date $4\n";
	$q->execute($date, $4, $date)
		or die "Couldn't push $1 into database";
	if (defined($owner_color)) {
		$cq->execute($owner_color, $4)
			or die "Couldn't push $1 into database";
	}
}
close SYSLOG;

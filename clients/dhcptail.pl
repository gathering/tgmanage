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

my ($dbh, $q);
$dbh = nms::db_connect();
$q = $dbh->prepare("INSERT INTO dhcp (switch,time,mac) VALUES((SELECT switch FROM switches WHERE ?::inet << network),?,?)");
open(SYSLOG, "tail -n 9999999 -F /var/log/syslog |") or die "Unable to tail syslog: $!";
while (<SYSLOG>) {
	/(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+(\d+)\s+(\d+:\d+:\d+).*DHCPACK on (\d+\.\d+\.\d+\.\d+) to (\S+)/ or next;
	my $date = $year . "-" . $months{$1} . "-" . $2 . " " . $3;
	my $machine = $5;
	$q->execute($4,$date,$machine);
	$q->commit;
}
close SYSLOG;

#! /usr/bin/perl
use strict;
use warnings;
use BER;
use DBI;
use POSIX;
use Time::HiRes;
use Net::Ping;

use lib '../include';
use nms;
use threads;

poll_loop();	

sub poll_loop {
	my $dbh = nms::db_connect();
	my $qcores = $dbh->prepare('SELECT DISTINCT coreswitches.sysname, coreswitches.switch, coreswitches.ip, coreswitches.community FROM uplinks JOIN switches AS coreswitches ON (uplinks.coreswitch = coreswitches.switch)');
	my $qaps = $dbh->prepare("SELECT switches.sysname, switches.switch, uplinks.blade, uplinks.port FROM uplinks NATURAL JOIN switches WHERE uplinks.coreswitch = ?");
	my $qpoll = $dbh->prepare("UPDATE ap_poll SET model=?, last_poll=now() WHERE switch = ?");

	while (1) {
		$qcores->execute();
		my $cores = $qcores->fetchall_hashref("sysname");

		foreach my $core (keys %$cores) {
			my $ip = $cores->{$core}{'ip'};
			my $community = $cores->{$core}{'community'};
			printf "Polling %s (%s)\n", $core, $ip;
			eval {
				my $session = nms::snmp_open_session($ip, $community);
				$qaps->execute($cores->{$core}{'switch'});
				while (my $aps = $qaps->fetchrow_hashref()) {
					my $sysname = $aps->{'sysname'};
					my $blade = $aps->{'blade'};
					my $port = $aps->{'port'};
					my $oid = "1.3.6.1.2.1.105.1.1.1.9.$blade.$port";     # POWER-ETHERNET-MIB...pethPsePortType
					my $mode = $session->get_request(-varbindlist=>[$oid])->{$oid};
					$qpoll->execute($mode, $aps->{'switch'});
					printf "%s (%s:%s/%s): %s\n", $sysname, $core, $blade, $port, $mode;
				}
			};
			if ($@) {
				mylog("ERROR: $@ (during poll of $ip)");
				$dbh->rollback;
			}
		}
		sleep 2;
	}
}

sub mylog {
	my $msg = shift;
	my $time = POSIX::ctime(time);
	$time =~ s/\n.*$//;
	printf STDERR "[%s] %s\n", $time, $msg;
}



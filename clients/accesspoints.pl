#! /usr/bin/perl
use strict;
use warnings;
use BER;
use DBI;
use POSIX;
use Time::HiRes;
use Net::Ping;
require 'SNMP_Session.pm';

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
				my $session = SNMPv2c_Session->open($ip, $community, 161) or die "Couldn't talk to switch";
				$qaps->execute($cores->{$core}{'switch'});
				while (my $aps = $qaps->fetchrow_hashref()) {
					my $sysname = $aps->{'sysname'};
					my $blade = $aps->{'blade'};
					my $port = $aps->{'port'};
					my $oid = BER::encode_oid(1,3,6,1,2,1,105,1,1,1,9,$blade,$port);     # POWER-ETHERNET-MIB...pethPsePortType
					my $mode = fetch_snmp($session, $oid);
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

# Kokt fra snmpfetch.pl, vi bør nok lage et lib
sub fetch_snmp {
        my ($session, $oid) = @_;

        if ($session->get_request_response($oid)) {
                my ($bindings) = $session->decode_get_response ($session->{pdu_buffer});
                my $binding;
                while ($bindings ne '') {
                        ($binding,$bindings) = &decode_sequence ($bindings);
                        my ($oid,$value) = &decode_by_template ($binding, "%O%@");
                        return BER::pretty_print($value);
                }
        }
        die "Couldn't get info from switch";
}

sub mylog {
	my $msg = shift;
	my $time = POSIX::ctime(time);
	$time =~ s/\n.*$//;
	printf STDERR "[%s] %s\n", $time, $msg;
}



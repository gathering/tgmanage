#! /usr/bin/perl
use DBI;
use POSIX;
use Time::HiRes;
use Net::Telnet;
use strict;
use warnings;
use Net::SNMP;

use lib '../include';
use nms;
use threads;

my $in_octets_oid = "1.3.6.1.2.1.31.1.1.1.6";    # interfaces.ifTable.ifEntry.ifHCInOctets
my $out_octets_oid = "1.3.6.1.2.1.31.1.1.1.10";  # interfaces.ifTable.ifEntry.ifHCOutOctets
my $in_errors_oid = "1.3.6.1.2.1.2.2.1.14";      # interfaces.ifTable.ifEntry.ifInErrors
my $out_errors_oid = "1.3.6.1.2.1.2.2.1.20";     # interfaces.ifTable.ifEntry.ifOutErrors

# normal mode: fetch switches from the database
# instant mode: poll the switches specified on the command line
if (defined($ARGV[0])) {
	poll_loop(@ARGV);
} else {
	my $threads = 50;
	for (1..$threads) {
		threads->create(\&poll_loop);
	}
	poll_loop();	
}

sub poll_loop {
	my @switches = @_;
	my $instant = (scalar @switches > 0);
	my $timeout = 15;

	my $dbh = nms::db_connect();
	$dbh->{AutoCommit} = 0;

	my $qualification;
	if ($instant) {
		$qualification = "sysname=?";
	} else {
		$qualification = <<"EOF";
  (last_updated IS NULL OR now() - last_updated > poll_frequency)
  AND (locked='f' OR now() - last_updated > '15 minutes'::interval)
  AND ip is not null
EOF
	}

	my $qswitch = $dbh->prepare(<<"EOF")
SELECT 
  *,
  DATE_TRUNC('second', now() - last_updated - poll_frequency) AS overdue
FROM
  switches
  NATURAL LEFT JOIN switchtypes
WHERE $qualification
ORDER BY
  priority DESC,
  overdue DESC
LIMIT 1
FOR UPDATE OF switches
EOF
		or die "Couldn't prepare qswitch";
	my $qlock = $dbh->prepare("UPDATE switches SET locked='t', last_updated=now() WHERE switch=?")
		or die "Couldn't prepare qlock";
	my $qunlock = $dbh->prepare("UPDATE switches SET locked='f', last_updated=now() WHERE switch=?")
		or die "Couldn't prepare qunlock";
	my $qpoll = $dbh->prepare("INSERT INTO polls (time, switch, port, bytes_in, bytes_out, errors_in, errors_out, official_port) VALUES (current_timestamp,?,?,?,?,?,?,?)")
		or die "Couldn't prepare qpoll";
	my $qtemppoll = $dbh->prepare("INSERT INTO temppoll (time, switch, temp) VALUES (timeofday()::timestamp,?::text::int,?::text::float)")
		or die "Couldn't prepare qtemppoll";
	my $qcpupoll = $dbh->prepare("INSERT INTO cpuloadpoll (time, switch, entity, value) VALUES (timeofday()::timestamp,?::text::int,?,?)")
		or die "Couldn't prepare qtemppoll";

	while (1) {
		my $sysname;
		if ($instant) {
			$sysname = shift @ARGV;
			exit if (!defined($sysname));
			$qswitch->execute($sysname)
				or die "Couldn't get switch";
		} else {
			# Find a switch to grab
			$qswitch->execute()
				or die "Couldn't get switch";
		}
		my $switch = $qswitch->fetchrow_hashref();

		if (!defined($switch)) {
			$dbh->commit;

			if ($instant) {
				mylog("No such switch $sysname available, quitting.");
				exit;
			} else {	
				mylog("No available switches in pool, sleeping.");
				sleep 15;
				next;
			}
		}

		$qlock->execute($switch->{'switch'})
			or die "Couldn't lock switch";
		$dbh->commit;

		if ($switch->{'locked'}) {
			mylog("WARNING: Lock timed out on $switch->{'ip'}, breaking lock");
		}

		my $msg;
		if (defined($switch->{'overdue'})) {
			$msg = sprintf "Polling ports %s on %s (%s), %s overdue.",
				$switch->{'ports'}, $switch->{'ip'}, $switch->{'sysname'}, $switch->{'overdue'};
		} else {
			$msg = sprintf "Polling ports %s on %s (%s), never polled before.",
				$switch->{'ports'}, $switch->{'ip'}, $switch->{'sysname'};
		}
		mylog($msg);

		my $ip = $switch->{'ip'};

		if ($ip eq '127.0.0.1') {
			mylog("Polling disabled for this switch, skipping.");
			$qunlock->execute($switch->{'switch'})
				or die "Couldn't unlock switch";
			$dbh->commit;
			next;
		}

		my $community = $switch->{'community'};
		my $start = [Time::HiRes::gettimeofday];
		eval {
			my $session = nms::snmp_open_session($ip, $community);

			my %ports = ();
			for my $port (expand_ports($switch->{'ports'})) {
				$ports{$port} = 1;
			}

			my $in_result = $session->get_table(
				-maxrepetitions => 200,
				-baseoid => $in_octets_oid,
			);
			my $out_result = $session->get_table(
				-maxrepetitions => 200,
				-baseoid => $out_octets_oid,
			);
			my $ine_result = $session->get_table(
				-maxrepetitions => 200,
				-baseoid => $in_errors_oid,
			);
			my $oute_result = $session->get_table(
				-maxrepetitions => 200,
				-baseoid => $out_errors_oid,
			);
			die "SNMP fetch failed: " . $session->error() if (!defined($in_result));

			for my $key (keys %$in_result) {
				(my $port = $key) =~ s/^\Q$in_octets_oid\E\.//;
				my $in = $in_result->{$in_octets_oid . '.' . $port};
				my $out = $out_result->{$out_octets_oid . '.' . $port};
				my $ine = $ine_result->{$in_errors_oid . '.' . $port};
				my $oute = $oute_result->{$out_errors_oid . '.' . $port};
				my $official_port = exists($ports{$port}) ? 1 : 0;
				$qpoll->execute($switch->{'switch'}, $port, $in, $out, $ine, $oute, $official_port) || die "%s:%s: %s\n", $switch->{'switch'}, $port, $in;
			}
			$session->close;
		};
		if ($@) {
			mylog("ERROR: $@ (during poll of $ip)");
			$dbh->rollback;
		}
		
		my $elapsed = Time::HiRes::tv_interval($start);
		$msg = sprintf "Polled $switch->{'ip'} in %5.3f seconds.", $elapsed;		
		mylog($msg);

		$qunlock->execute($switch->{'switch'})
			or warn "Couldn't unlock switch";
		$dbh->commit;
	}
}

sub expand_ports {
	my $in = shift;
	my @ranges = split /,/, $in;
	my @ret = ();

	for my $range (@ranges) {
		if ($range =~ /^\d+$/) {
			push @ret, $range;
		} elsif ($range =~ /^(\d+)-(\d+)$/) {
			for my $i ($1..$2) {
				push @ret, $i;
			}
		} else {
			die "Couldn't understand '$range' in ports";
		}
	}

	return (sort { $a <=> $b } @ret); 
}

sub mylog {
	my $msg = shift;
	my $time = POSIX::ctime(time);
	$time =~ s/\n.*$//;
	printf STDERR "[%s] %s\n", $time, $msg;
}

#sub switch_exec {
#	my ($cmd, $conn) = @_;
#
#	# Send the command and get data from switch
##	$conn->dump_log(*STDOUT);
#	my @data = $conn->cmd($cmd);
#	my @lines = ();
#	foreach my $line (@data) {
#		# Remove escape-7 sequence
#		$line =~ s/\x1b\x37//g;
#		push @lines, $line;
#	}
#
#	return @lines;
#}

#sub switch_connect {
#	my ($ip) = @_;
#
#	my $conn = new Net::Telnet(     Timeout => $timeout,
#					Dump_Log => '/tmp/dumplog-tempfetch',
#					Errmode => 'return',
#					Prompt => '/es-3024|e(\-)?\d+\-\dsw>/i');
#	my $ret = $conn->open(  Host => $ip);
#	if (!$ret || $ret != 1) {
#		return (0);
#	}
#	# XXX: Just send the password as text, I did not figure out how to
#	# handle authentication with only password through $conn->login().
#	#$conn->login(  Prompt => '/password[: ]*$/i',
#	#	       Name => $password,
#	#	       Password => $password);
#	my @data = $conn->cmd($password);
#	# Get rid of banner
#	$conn->get;
#	return $conn;
#}


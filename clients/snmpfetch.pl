#! /usr/bin/perl
use DBI;
use POSIX;
use Time::HiRes;
use Net::Telnet;
use strict;
use warnings;

use lib '../include';
use nms;
use threads;

our $running = 0;

our $dbh = nms::db_connect();
$dbh->{AutoCommit} = 0;
$dbh->{RaiseError} = 1;

# normal mode: fetch switches from the database
# instant mode: poll the switches specified on the command line
my $instant = defined($ARGV[0]);

my $qualification;
if ($instant) {
	$qualification = "sysname LIKE ?";
} else {
	$qualification = <<"EOF";
(last_updated IS NULL OR now() - last_updated > poll_frequency)
AND (locked='f' OR now() - last_updated > '5 minutes'::interval)
AND ip is not null
EOF
}

our $qswitch = $dbh->prepare(<<"EOF")
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
our $qlock = $dbh->prepare("UPDATE switches SET locked='t', last_updated=now() WHERE switch=?")
	or die "Couldn't prepare qlock";
our $qunlock = $dbh->prepare("UPDATE switches SET locked='f', last_updated=now() WHERE switch=?")
	or die "Couldn't prepare qunlock";
our $qpoll = $dbh->prepare("INSERT INTO polls (time, switch, port, bytes_in, bytes_out, errors_in, errors_out, official_port) VALUES (timeofday()::timestamp,?,?,?,?,?,?,true)")
	or die "Couldn't prepare qpoll";

poll_loop(@ARGV);
while ($running > 0) {
	SNMP::MainLoop(0.1);
}

sub poll_loop {
	my @switches = @_;
	my $instant = (scalar @switches > 0);
	my $timeout = 15;

	while (1) {
		my $sysname;
		if ($instant) {
			$sysname = shift @ARGV;
			return if (!defined($sysname));
			$qswitch->execute('%'.$sysname.'%')
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
				return;
			} else {	
				mylog("No available switches in pool, sleeping.");
				SNMP::MainLoop(1.0);
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
		my $session;
		eval {
			$session = nms::snmp_open_session($ip, $community, 1);
		};
		if ($@) {
			warn "Couldn't open session (even an async one!) to $ip: $!";
			$qunlock->execute($switch->{'switch'})
				or die "Couldn't unlock switch";
			$dbh->commit;
			next;
		};
		my @ports = expand_ports($switch->{'ports'});

		my $switch_status = {
			session => $session,
			ip => $switch->{'ip'},
			sysname => $switch->{'sysname'},
			switch => $switch->{'switch'},
			num_ports => scalar @ports,
			num_done => 0,
			start => $start,
		};	

		for my $port (@ports) {
			my @vars = ();
			push @vars, ["ifInOctets", $port];
			push @vars, ["ifOutOctets", $port];
			push @vars, ["ifInErrors", $port];
			push @vars, ["ifOutErrors", $port];
			my $varlist = SNMP::VarList->new(@vars);
			$session->get($varlist, [ \&callback, $switch_status, $port ]);
		}
		$running++;

		$dbh->rollback;
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

sub callback {
	my ($switch, $port, $vars) = @_;

	my ($in, $out, $ine, $oute) = (undef, undef, undef, undef);

	for my $var (@$vars) {
		if ($port != $var->[1]) {
			die "Response for unknown OID $var->[0].$var->[1] (expected port $port)";
		}
		if ($var->[0] eq 'ifInOctets') {
			$in = $var->[2];
		} elsif ($var->[0] eq 'ifOutOctets') {
			$out = $var->[2];
		} elsif ($var->[0] eq 'ifInErrors') {
			$ine = $var->[2];
		} elsif ($var->[0] eq 'ifOutErrors') {
			$oute = $var->[2];
		} else {
			die "Response for unknown OID $var->[0].$var->[1]";
		}
	}

	my $ok = 1;
	if (!defined($in) || $in !~ /^\d+$/) {
		if (defined($ine)) {
			warn $switch->{'sysname'}.":$port: failed reading in";
		}
		$ok = 0;	
		warn "no in";
	}
	if (!defined($out) || $out !~ /^\d+$/) {
		if (defined($oute)) {
			warn $switch->{'sysname'}.":$port: failed reading in";
		}
		$ok = 0;	
		warn "no out";
	}

	if ($ok) {
		$qpoll->execute($switch->{'switch'}, $port, $in, $out, $ine, $oute) || die "%s:%s: %s\n", $switch->{'switch'}, $port, $in;
		$dbh->commit;
	} else {
		warn $switch->{'sysname'} . " failed to OK.";
	}

	if (++$switch->{'num_done'} == $switch->{'num_ports'}) {
		--$running;
		
		my $elapsed = Time::HiRes::tv_interval($switch->{'start'});
		my $msg = sprintf "Polled $switch->{'ip'} in %5.3f seconds.", $elapsed;		
		mylog($msg);

		$qunlock->execute($switch->{'switch'})
			or warn "Couldn't unlock switch";
		$dbh->commit;
	}
}

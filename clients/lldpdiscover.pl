#! /usr/bin/perl
use DBI;
use POSIX;
use Time::HiRes;
use strict;
use warnings;

use lib '../include';
use nms;

my $dbh = nms::db_connect();
$dbh->{AutoCommit} = 0;

# If we are given one switch on the command line, poll that and then exit.
my ($cmdline_ip, $cmdline_community) = @ARGV;
if (defined($cmdline_ip) && defined($cmdline_community)) {
	eval {
		discover_lldp_neighbors($dbh, $cmdline_ip, $cmdline_community);
	};
	if ($@) {
		mylog("ERROR: $@ (during poll of $cmdline_ip)");
		$dbh->rollback;
	}
	$dbh->disconnect;
	exit;
}

# First, find all machines that lack an LLDP chassis ID.
my $q = $dbh->prepare("SELECT switch, ip, community FROM switches WHERE lldp_chassis_id IS NULL AND ip <> '127.0.0.1'");
$q->execute;

while (my $ref = $q->fetchrow_hashref) {
	my ($switch, $ip, $community) = ($ref->{'switch'}, $ref->{'ip'}, $ref->{'community'});
	eval {
		my $session = nms::snmp_open_session($ip, $community);

		# Cisco returns completely bogus values if we use get()
		# on lldpLocChassisId.0, it seems. Work around it by using getnext().
		my $response = $session->getnext('lldpLocChassisId');
		my $chassis_id = nms::convert_mac($response);
		die "SNMP error: " . $session->error() if (!defined($chassis_id));
		$dbh->do('UPDATE switches SET lldp_chassis_id=? WHERE switch=?', undef,
			$chassis_id, $switch);
		mylog("Set chassis ID for $ip to $chassis_id.");
	};
	if ($@) {
		mylog("ERROR: $@ (during poll of $ip)");
		$dbh->rollback;
	}
}

# Now ask all switches for their LLDP neighbor table.
$q = $dbh->prepare("SELECT ip, community FROM switches WHERE lldp_chassis_id IS NOT NULL AND ip <> '127.0.0.1'");
$q->execute;

while (my $ref = $q->fetchrow_hashref) {
	my ($ip, $community) = ($ref->{'ip'}, $ref->{'community'});
	eval {
		discover_lldp_neighbors($dbh, $ip, $community);
	};
	if ($@) {
		mylog("ERROR: $@ (during poll of $ip)");
		$dbh->rollback;
	}
}

$dbh->disconnect;

sub discover_lldp_neighbors {
	my ($dbh, $ip, $community) = @_;
	my $qexist = $dbh->prepare('SELECT COUNT(*) AS cnt FROM switches WHERE lldp_chassis_id=?');

	my $session = nms::snmp_open_session($ip, $community);
	my $remtable = $session->gettable('lldpRemTable');
	my $addrtable;
	while (my ($key, $value) = each %$remtable) {
		my $chassis_id = nms::convert_mac($value->{'lldpRemChassisId'});
		my $sysname = $value->{'lldpRemSysName'};

		# Do not try to poll servers.
		my %caps = ();
		nms::convert_lldp_caps($value->{'lldpRemSysCapEnabled'}, \%caps);
		next if (!$caps{'cap_enabled_bridge'} && !$caps{'cap_enabled_ap'} && !$caps{'cap_enabled_router'});

		my $exists = $dbh->selectrow_hashref($qexist, undef, $chassis_id)->{'cnt'};
		next if ($exists);

		# Pull in the management address table lazily.
		$addrtable = $session->gettable("lldpRemManAddrTable") if (!defined($addrtable));

		# Search for this key in the address table.
		my @v4addrs = ();
		my @v6addrs = ();
		while (my ($addrkey, $addrvalue) = each %$addrtable) {
			#next unless $addrkey =~ /^\Q$key\E\.1\.4\.(.*)$/;  # 1.4 = ipv4, 2.16 = ipv6
			next unless $addrkey =~ /^\Q$key\E\./;  # 1.4 = ipv4, 2.16 = ipv6
			my $addr = $addrvalue->{'lldpRemManAddr'};
			my $addrtype = $addrvalue->{'lldpRemManAddrSubtype'};
			if ($addrtype == 1) {
				push @v4addrs, nms::convert_ipv4($addr);
			} elsif ($addrtype == 2) {
				push @v6addrs, nms::convert_ipv6($addr);
			} else {
				die "Unknown address type $addr";
			}
		}
		my $addr;
		if (scalar @v6addrs > 0) {
			$addr = $v6addrs[0];
		} elsif (scalar @v4addrs > 0) {
			$addr = $v4addrs[0];
		} else {
			warn "Could not find a management address for chassis ID $chassis_id (sysname=$sysname, lldpRemIndex=$key)";
			next;
		}

		# Yay, a new switch! Make a new type for it.
		# We simply guess that the community is the same as ours.
		# TODO(sesse): Autopopulate ports from type.
		# TODO(sesse): Autopopulate port names.
		mylog("Inserting new switch $sysname ($addr).");
		my $switchtype = "auto-$sysname-$chassis_id";
		$dbh->do('INSERT INTO switchtypes (switchtype, ports) VALUES (?, ?)', undef,
			$switchtype, '');
		$dbh->do('INSERT INTO switches (ip, sysname, switchtype, community, lldp_chassis_id) VALUES (?, ?, ?, ?, ?)', undef,
			$addr, $sysname, $switchtype, $community, $chassis_id);
		$dbh->commit;
	}
}

sub mylog {
	my $msg = shift;
	my $time = POSIX::ctime(time);
	$time =~ s/\n.*$//;
	printf STDERR "[%s] %s\n", $time, $msg;
}

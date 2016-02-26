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

# If we are given one switch on the command line, add that and then exit.
my ($cmdline_ip, $cmdline_community) = @ARGV;
if (defined($cmdline_ip) && defined($cmdline_community)) {
	eval {
		my $session = nms::snmp_open_session($cmdline_ip, $cmdline_community);
		my $sysname = $session->get('sysName.0');
		my $chassis_id = get_lldp_chassis_id($session);
		add_switch($dbh, $cmdline_ip, $sysname, $chassis_id, $cmdline_community);
	};
	if ($@) {
		mylog("ERROR: $@ (during poll of $cmdline_ip)");
		$dbh->rollback;
	}
	$dbh->disconnect;
	exit;
}

# Find all candidate SNMP communities.
my $snmpq = $dbh->prepare("SELECT DISTINCT community FROM switches");
$snmpq->execute;
my @communities = ();
while (my $ref = $snmpq->fetchrow_hashref) {
	push @communities, $ref->{'community'};
}

# First, find all machines that lack an LLDP chassis ID.
my $q = $dbh->prepare("SELECT switch, ip, community FROM switches WHERE lldp_chassis_id IS NULL AND ip <> '127.0.0.1' and switchtype <> 'ex2200'");
$q->execute;

while (my $ref = $q->fetchrow_hashref) {
	my ($switch, $ip, $community) = ($ref->{'switch'}, $ref->{'ip'}, $ref->{'community'});
	eval {
		my $session = nms::snmp_open_session($ip, $community);
		my $chassis_id = get_lldp_chassis_id($session);
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
$dbh->commit;

# Now ask all switches for their LLDP neighbor table.
$q = $dbh->prepare("SELECT ip, sysname, community FROM switches WHERE lldp_chassis_id IS NOT NULL AND ip <> '127.0.0.1' AND switchtype <> 'ex2200'");
$q->execute;

while (my $ref = $q->fetchrow_hashref) {
	my ($ip, $sysname, $community) = ($ref->{'ip'}, $ref->{'sysname'}, $ref->{'community'});
	eval {
		discover_lldp_neighbors($dbh, $ip, $sysname, $community);
	};
	if ($@) {
		mylog("ERROR: $@ (during poll of $ip)");
		$dbh->rollback;
	}
	$dbh->commit;
}

$dbh->disconnect;

sub discover_lldp_neighbors {
	my ($dbh, $ip, $local_sysname, $community) = @_;
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
		next if (!$caps{'cap_enabled_bridge'} && !$caps{'cap_enabled_router'});
		next if ($caps{'cap_enabled_ap'});
		next if ($caps{'cap_enabled_telephone'});

		next if $sysname =~ /nocnexus/;

		my $sysdesc = $value->{'lldpRemSysDesc'};
		next if $sysdesc =~ /\b(C1530|C3600|C3700)\b/;

		my $exists = $dbh->selectrow_hashref($qexist, undef, $chassis_id)->{'cnt'};
		next if ($exists);

		print "Found $local_sysname -> $sysname ($chassis_id)\n";

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
				my $v6addr = nms::convert_ipv6($addr);
				next if $v6addr =~ /^fe80:/;  # Ignore link-local.
				push @v6addrs, $v6addr;
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

		# We simply guess that the community is the same as ours.
		add_switch($dbh, $addr, $sysname, $chassis_id, @communities);
	}
}

sub mylog {
	my $msg = shift;
	my $time = POSIX::ctime(time);
	$time =~ s/\n.*$//;
	printf STDERR "[%s] %s\n", $time, $msg;
}

sub get_ports {
	my ($ip, $sysname, $community) = @_;
	my $ret = undef;
	eval {
		my $session = nms::snmp_open_session($ip, $community);
		$ret = $session->gettable('ifTable', columns => [ 'ifType', 'ifDescr' ]);
	};
	if ($@) {
		mylog("Error during SNMP to $ip ($sysname): $@");
		return undef;
	}
	return $ret;
}

sub get_ifindex_for_physical_ports {
	my $ports = shift;
	my @indices = ();
	for my $port (values %$ports) {
		next unless ($port->{'ifType'} eq 'ethernetCsmacd');
		push @indices, $port->{'ifIndex'};
	}
	return @indices;
}

sub compress_ports {
	my (@ports) = @_;
	my $current_range_start = undef;
	my $last_port = undef;

	my @ranges = ();
	for my $port (sort { $a <=> $b } (@ports)) {
		if (!defined($current_range_start)) {
			# First element.
			$current_range_start = $last_port = $port;
			next;
		}
		if ($port == $last_port + 1) {
			# Just extend the current range.
			++$last_port;
		} else {
			push @ranges, range_from_to($current_range_start, $last_port);
			$current_range_start = $last_port = $port;
		}
	}
	push @ranges, range_from_to($current_range_start, $last_port);
	return join(',', @ranges);
}

sub range_from_to {
	my ($from, $to) = @_;
	if ($from == $to) {
		return $from;
	} else {
		return "$from-$to";
	}
}

sub add_switch {
	my ($dbh, $addr, $sysname, $chassis_id, @communities) = @_;

	# Yay, a new switch! Make a new type for it.
	my $ports;
	my $community;
	for my $cand_community (@communities) {
		$community = $cand_community;
		$ports = get_ports($addr, $sysname, $community);
		last if (defined($ports));
	}
	return if (!defined($ports));
	my $portlist = compress_ports(get_ifindex_for_physical_ports($ports));
	mylog("Inserting new switch $sysname ($addr, ports $portlist).");
	my $switchtype = "auto-$sysname-$chassis_id";
	$dbh->do('INSERT INTO switchtypes (switchtype, ports) VALUES (?, ?)', undef,
		$switchtype, $portlist);
	$dbh->do('INSERT INTO switches (ip, sysname, switchtype, community, lldp_chassis_id) VALUES (?, ?, ?, ?, ?)', undef,
		$addr, $sysname, $switchtype, $community, $chassis_id);
	for my $port (values %$ports) {
		$dbh->do('INSERT INTO portnames (switchtype, port, description) VALUES (?, ?, ?)',
			undef, $switchtype, $port->{'ifIndex'}, $port->{'ifDescr'});
	}

	# Entirely random placement. Annoying? Fix it yourself.
	my $x = int(rand 1200);
	my $y = int(rand 650);
	my $box = sprintf "((%d,%d),(%d,%d))", $x, $y, $x+40, $y+40;
	$dbh->do("INSERT INTO placements (switch,placement) VALUES (CURRVAL('switches_switch_seq'), ?)",
		undef, $box);

	$dbh->commit;
}

sub get_lldp_chassis_id {
	my ($session) = @_;

	# Cisco returns completely bogus values if we use get()
	# on lldpLocChassisId.0, it seems. Work around it by using getnext().
	my $response = $session->getnext('lldpLocChassisId');
	return nms::convert_mac($response);
}

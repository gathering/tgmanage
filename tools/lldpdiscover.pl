#! /usr/bin/perl
use DBI;
use POSIX;
use Time::HiRes;
use strict;
use warnings;
use Data::Dumper;

use lib 'tgmanage/include';
use nms;

# Actual assets detected, indexed by chassis ID
my %assets;

# Tracking arrays. Continue scanning until they are of the same length.
my @chassis_ids_checked;
my @chassis_ids_to_check;

# If we are given one switch on the command line, add that and then exit.
my ($cmdline_ip, $cmdline_community) = @ARGV;
if (defined($cmdline_ip) && defined($cmdline_community)) {
	eval {
		# Special-case for the first switch is to fetch chassis id
		# directly. Everything else is fetched from a neighbour
		# table.
		my $session = nms::snmp_open_session($cmdline_ip, $cmdline_community);
		my $chassis_id = get_lldp_chassis_id($session);
		$assets{$chassis_id}{'community'} = $cmdline_community;
		@{$assets{$chassis_id}{'v4mgmt'}} = ($cmdline_ip);
		@{$assets{$chassis_id}{'v6mgmt'}} = ();
		push @chassis_ids_to_check, $chassis_id;
	};
	if ($@) {
		mylog("Error during SNMP  : $@");
		exit 1;
	}

	# Welcome to the main loop!
	while (scalar @chassis_ids_to_check > scalar @chassis_ids_checked) {
		# As long as you call it something else, it's not really a
		# goto-statement, right!?
		OUTER: for my $id (@chassis_ids_to_check) {
			for my $id2 (@chassis_ids_checked) {
				if ($id2 eq $id) {
					next OUTER;
				}
			}
			mylog("Adding $id");
			add_switch($id);
			mylog("Discovering neighbors for $id");
			discover_lldp_neighbors($id);
			push @chassis_ids_checked,$id;
		}
	}
	print JSON::XS::encode_json(\%assets);
	exit;
} else {
	print "RTFSC\n";
}

# Filter out stuff we don't scan. Return true if we care about it.
# XXX: Several of these things are temporary to test (e.g.: AP).
sub filter {
	my %sys = %{$_[0]};
	my %caps = %{$sys{'lldpRemSysCapEnabled'}};
	my $sysdesc = $sys{'lldpRemSysDesc'};
	my $sysname = $sys{'lldpRemSysName'};

	if ($caps{'cap_enabled_ap'}) {
		return 1;
	}
	if ($caps{'cap_enabled_telephone'}) {
		return 0;
	}
	if ($sysdesc =~ /\b(C1530|C3600|C3700)\b/) {
		return 0;
	}
	if (!$caps{'cap_enabled_bridge'} && !$caps{'cap_enabled_router'}) {
		return 1;
	}
	if ($sysname =~ /BCS-OSL/) {
		return 1;
	}
	return 1;
}

# Discover neighbours of a switch. The data needed is already present int
# %assets , so this shouldn't cause any extra SNMP requests. It will add
# new devices as it finds them.
sub discover_lldp_neighbors {
	my $local_id = $_[0];
	my $ip = $assets{$local_id}{mgmt};
	my $local_sysname = $assets{$local_id}{snmp}{sysName};
	my $community = $assets{$local_id}{community};
	my $addrtable;
	while (my ($key, $value) = each %{$assets{$local_id}{snmp_parsed}{lldpRemTable}}) {
		my $chassis_id = $value->{'lldpRemChassisId'};
		my $sysname = $value->{'lldpRemSysName'};

		# Do not try to poll servers.
		if (!filter(\%{$value})) {
			mylog("Filtered out $sysname  ($local_sysname -> $sysname)");
			next;
		}

		# Pull in the management address table lazily.
		$addrtable = $assets{$local_id}{snmp_parsed}{lldpRemManAddrTable}{$key};

		# Search for this key in the address table.
		my @v4addrs = ();
		my @v6addrs = ();
		while (my ($addrkey, $addrvalue) = each %$addrtable) {
			my $addr = $addrvalue->{'lldpRemManAddr'};
			my $addrtype = $addrvalue->{'lldpRemManAddrSubtype'};
			if ($addrtype == 1) {
				push @v4addrs, $addr;
			} elsif ($addrtype == 2) {
				my $v6addr = $addr;
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

		mylog("Found $sysname ($local_sysname -> $sysname ($addr))");
		$sysname =~ s/\..*$//;
		$assets{$chassis_id}{'sysName'} = $sysname;
		# We simply guess that the community is the same as ours.
		$assets{$chassis_id}{'community'} = $community;
		@{$assets{$chassis_id}{'v4mgmt'}} = @v4addrs;
		@{$assets{$chassis_id}{'v6mgmt'}} = @v6addrs;

		$assets{$chassis_id}{'neighbors'}{$local_id} = 1;
		$assets{$local_id}{'neighbors'}{$chassis_id} = 1;
		check_neigh($chassis_id);
	}
}

sub mylog {
	my $msg = shift;
	my $time = POSIX::ctime(time);
	$time =~ s/\n.*$//;
	printf STDERR "[%s] %s\n", $time, $msg;
}

# Get raw SNMP data for an ip/community.
sub get_snmp_data {
	my ($ip, $community) = @_;
	my %ret = ();
	eval {
		my $session = nms::snmp_open_session($ip, $community);
		$ret{'sysName'} = $session->get('sysName.0');
		$ret{'sysDescr'} = $session->get('sysDescr.0');
		$ret{'lldpRemManAddrTable'} = $session->gettable("lldpRemManAddrTable");
		$ret{'lldpRemTable'} = $session->gettable("lldpRemTable");
		$ret{'ifTable'} = $session->gettable('ifTable', columns => [ 'ifType', 'ifDescr' ]);
		$ret{'ifXTable'} = $session->gettable('ifXTable', columns => [ 'ifHighSpeed', 'ifName' ]);
		$ret{'lldpLocChassisId'} = $session->get('lldpLocChassisId.0');
	};
	if ($@) {
		mylog("Error during SNMP to $ip : $@");
		return undef;
	}
	return \%ret;
}

# Filter raw SNMP data over to something more legible.
# This is the place to add all post-processed results so all parts of the
# tool can use them.
sub parse_snmp
{
	my $snmp = $_[0];
	my %result = ();
	while (my ($key, $value) = each %{$snmp}) {
		$result{$key} = $value;
	}
	$result{lldpLocChassisId} = nms::convert_mac($snmp->{'lldpLocChassisId'});
	while (my ($key, $value) = each %{$snmp->{lldpRemTable}}) {
		my $id = $key;
		my $chassis_id = nms::convert_mac($value->{'lldpRemChassisId'});
		my $sysname = $value->{'lldpRemSysName'};
		foreach my $key2 (keys %$value) {
			$result{lldpRemTable}{$id}{$key2} = $value->{$key2};
		}
		$result{lldpRemTable}{$id}{'lldpRemChassisId'} = $chassis_id;
		my %caps = ();
		nms::convert_lldp_caps($value->{'lldpRemSysCapEnabled'}, \%caps);
		$result{lldpRemTable}{$id}{'lldpRemSysCapEnabled'} = \%caps; 
	}
	$result{lldpRemManAddrTable} = ();
	while (my ($key, $value) = each %{$snmp->{lldpRemManAddrTable}}) {
		my %tmp = ();
		foreach my $key2 (keys %$value) {
			$tmp{$key2} = $value->{$key2};
		}
		my $addr = $value->{'lldpRemManAddr'};
		my $addrtype = $value->{'lldpRemManAddrSubtype'};
		if ($addrtype == 1) {
			$tmp{lldpRemManAddr} = nms::convert_ipv4($addr);
		} elsif ($addrtype == 2) {
			$tmp{lldpRemManAddr} = nms::convert_ipv6($addr);
		}
		my $id = $value->{lldpRemTimeMark} . "." . $value->{lldpRemLocalPortNum} . "." . $value->{lldpRemIndex};
		my $id2 = $tmp{lldpRemManAddr};
		$result{lldpRemManAddrTable}{$id}{$id2} = \%tmp;
	}
	return \%result;
}

# Add a chassis_id to the list to be checked, but only if it isn't there.
# I'm sure there's some better way to do this, but meh, perl.
sub check_neigh {
	my $n = $_[0];
	for my $v (@chassis_ids_to_check) {
		if ($v eq $n) {
			return 0;
		}
	}
	push @chassis_ids_to_check,$n;
	return 1;
}

#
# We've got a switch. Populate it with SNMP data (if we can).
sub add_switch {
	my $chassis_id = shift;
	my @addrs;
	push @addrs, @{$assets{$chassis_id}{'v4mgmt'}};
	push @addrs, @{$assets{$chassis_id}{'v6mgmt'}};
	my $addr;
	my $snmp = undef;
	while (my $key = each @addrs ) {
		$addr = $addrs[$key];
		mylog("Probing $addr");
		$snmp = get_snmp_data($addr, $assets{$chassis_id}{'community'});
		if (defined($snmp)) {
			last;
		}

	}
	return if (!defined($snmp));
	$assets{$chassis_id}{'mgmt'} = $addr;
	$assets{$chassis_id}{'snmp'} = $snmp;
	$assets{$chassis_id}{'snmp_parsed'} = parse_snmp($snmp);
	$assets{$chassis_id}{'chassis_id_x'} =  nms::convert_mac($snmp->{'lldpLocChassisId'});
	return;
}

sub get_lldp_chassis_id {
	my ($session) = @_;
	my $response = $session->get('lldpLocChassisId.0');
	return nms::convert_mac($response);
}

#! /usr/bin/perl
use strict;
use warnings;
use DBI;
use Net::Telnet;
use Data::Dumper;
use FixedSNMP;
use FileHandle;
package nms;

use base 'Exporter';
our @EXPORT = qw(switch_disconnect switch_connect switch_exec switch_timeout db_connect);

BEGIN {
	require "config.pm";
	eval {
		require "config.local.pm";
	};

	# $SNMP::debugging = 1;

	# sudo mkdir /usr/share/mibs/site
	# cd /usr/share/mibs/site
	# wget -O- ftp://ftp.cisco.com/pub/mibs/v2/v2.tar.gz | sudo tar --strip-components=3 -zxvvf -
	SNMP::initMib();
	SNMP::loadModules('SNMPv2-MIB');
	SNMP::loadModules('ENTITY-MIB');
	SNMP::loadModules('IF-MIB');
	SNMP::loadModules('LLDP-MIB');
}

sub db_connect {
	my $connstr = "dbi:Pg:dbname=" . $nms::config::db_name;
	$connstr .= ";host=" . $nms::config::db_host unless (!defined($nms::config::db_host));

	my $dbh = DBI->connect($connstr,
	                       $nms::config::db_username,
	                       $nms::config::db_password)
	        or die "Couldn't connect to database";
	return $dbh;	
}

sub switch_connect($) {
	my ($ip) = @_;

	my $dumplog = FileHandle->new;
	$dumplog->open(">>/tmp/dumplog-queue") or die "/tmp/dumplog-queue: $!";
	$dumplog->print("\n\nConnecting to " . $ip . "\n\n");

	my $inputlog = FileHandle->new;
	$inputlog->open(">>/tmp/inputlog-queue") or die "/tmp/inputlog-queue: $!";
	$inputlog->print("\n\nConnecting to " . $ip . "\n\n");

	my $conn = new Net::Telnet(	Timeout => $nms::config::telnet_timeout,
					Dump_Log => $dumplog,
					Input_Log => $inputlog,
					Errmode => 'return',
					Prompt => '/DGS-3100# (?!\x1b\[K)/');
	my $ret = $conn->open(	Host => $ip);
	if (!$ret || $ret != 1) {
		return (undef);
	}
	# Handle login with and without password
	print "Logging in without password\n";
	$conn->waitfor('/User ?Name:/');
	$conn->print('admin');
	my (undef, $match) = $conn->waitfor('/DGS-3100#|Password:/');
	die 'Unexpected prompt after login attempt' if (not defined $match);
	if ($match eq 'Password:') {
		$conn->print('gurbagurba'); # Dette passordet skal feile
		$conn->waitfor('/User ?Name:/');
		$conn->print($nms::config::dlink1g_user);
		my (undef, $match) = $conn->waitfor('/DGS-3100#|Password:/');
		if ($match eq 'Password:') {
			$conn->cmd($nms::config::dlink1g_passwd);
		}
	}
	return ($conn);
}

# Send a command to switch and return the data recvied from the switch
sub switch_exec {
	my ($cmd, $conn, $print) = @_;

	# Send the command and get data from switch
	my @data;
	if (defined($print)) {
		$conn->print($cmd);
		return;
	} else {
		@data = $conn->cmd($cmd);
		print $conn->errmsg, "\n";
	}
	return @data;
#	my @lines = ();
#	foreach my $line (@data) {
#		# Remove escape-7 sequence
##		$line =~ s/\x1b\x37//g;
#		push (@lines, $line);
#	}
#	return @lines;
}
				
sub switch_timeout {
	my ($timeout, $conn) = @_;

	$conn->timeout($timeout);
	return ('Set timeout to ' . $timeout);
}

sub switch_disconnect {
	my ($conn) = @_;
	$conn->close;
}

sub snmp_open_session {
	my ($ip, $community) = @_;

	my %options = (UseEnums => 1);
	if ($ip =~ /:/) {
		$options{'DestHost'} = "udp6:$ip";
	} else {
		$options{'DestHost'} = "udp:$ip";
	}

	if ($community =~ /^snmpv3:(.*)$/) {
		my ($username, $authprotocol, $authpassword, $privprotocol, $privpassword) = split /\//, $1;

		$options{'SecName'} = $username;
		$options{'SecLevel'} = 'authNoPriv';
		$options{'AuthProto'} = $authprotocol;
		$options{'AuthPass'} = $authpassword;

		if (defined($privprotocol) && defined($privpassword)) {
			$options{'SecLevel'} = 'authPriv';
			$options{'PrivProto'} = $privprotocol;
			$options{'PrivPass'} = $privpassword;
		}

		$options{'Version'} = 3;
	} else {
		$options{'Version'} = 2;
	}

	my $session = SNMP::Session->new(%options);
	if (defined($session) && defined($session->getnext('sysDescr'))) {
		return $session;
	} else {
		die 'Could not open SNMP session';
	}
}

# Not currently in use; kept around for reference.
sub fetch_multi_snmp {
	my ($session, @oids) = @_;

	my %results = ();

	# Do bulk reads of 40 and 40; seems to be about the right size for 1500-byte packets.
	for (my $i = 0; $i < scalar @oids; $i += 40) {
		my $end = $i + 39;
		$end = $#oids if ($end > $#oids);
		my @oid_slice = @oids[$i..$end];

		my $localresults = $session->get_request(-varbindlist => \@oid_slice);
		return undef if (!defined($localresults));

		while (my ($key, $value) = each %$localresults) {
			$results{$key} = $value;
		}
	}

	return \%results;
}

# A few utilities to convert from SNMP binary address format to human-readable.

sub convert_mac {
	return join(':', map { sprintf "%02x", $_ } unpack('C*', shift));
}

sub convert_ipv4 {
	return join('.', map { sprintf "%d", $_ } unpack('C*', shift));
}

sub convert_ipv6 {
	return join(':', map { sprintf "%x", $_ } unpack('n*', shift));
}

sub convert_addr {
	my ($data, $type) = @_;
	if ($type == 1) {
		return convert_ipv4($data);
	} elsif ($type == 2) {
		return convert_ipv6($data);
	} else {
		die "Unknown address type $type";
	}
}

# Convert raw binary SNMP data to list of bits.
sub convert_bytelist {
	return split //, unpack("B*", shift);
}

sub convert_lldp_caps {
	my ($caps_data, $data) = @_;

        my @caps = convert_bytelist($caps_data);
        my @caps_names = qw(other repeater bridge ap router telephone docsis stationonly);
        for (my $i = 0; $i < scalar @caps && $i < scalar @caps_names; ++$i) {
		$data->{'cap_enabled_' . $caps_names[$i]} = $caps[$i];
        }
}

1;

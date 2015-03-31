#! /usr/bin/perl
use strict;
use warnings;
use DBI;
use Net::OpenSSH;
use Net::Telnet;
use Data::Dumper;
use FixedSNMP;
use FileHandle;
use JSON;
package nms;

use base 'Exporter';
our @EXPORT = qw(switch_disconnect switch_connect_ssh switch_connect_dlink switch_exec switch_exec_json switch_timeout db_connect);

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
	SNMP::loadModules('IP-MIB');
	SNMP::loadModules('IP-FORWARD-MIB');
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

sub switch_connect_ssh($) {
	my ($ip) = @_;
	my $ssh = Net::OpenSSH->new($ip, 
		user => $nms::config::tacacs_user,
		password => $nms::config::tacacs_pass,
		master_opts => [ "-o", "StrictHostKeyChecking=no" ]);
	my ($pty, $pid) = $ssh->open2pty({stderr_to_stdout => 1})
		or die "unable to start remote shell: " . $ssh->error;

	my $dumplog = FileHandle->new;
	$dumplog->open(">>/tmp/dumplog-queue") or die "/tmp/dumplog-queue: $!";
	#$dumplog->print("\n\nConnecting to " . $ip . "\n\n");

	my $inputlog = FileHandle->new;
	$inputlog->open(">>/tmp/inputlog-queue") or die "/tmp/inputlog-queue: $!";
	#$inputlog->print("\n\nConnecting to " . $ip . "\n\n");

	my $telnet = Net::Telnet->new(-fhopen => $pty,
				      -timeout => $nms::config::telnet_timeout,
				      -dump_log => $dumplog,
				      -input_log => $inputlog,
				      -prompt => '/.*\@e\d+-\d+[>#] /',
				      -telnetmode => 0,
				      -cmd_remove_mode => 1,
				      -output_record_separator => "\r");
	$telnet->waitfor(-match => $telnet->prompt,
	                 -errmode => "return")
		or die "login failed: " . $telnet->lastline;

	$telnet->cmd("set cli screen-length 0");

	return { telnet => $telnet, ssh => $ssh, pid => $pid, pty => $pty };
}

sub switch_connect_dlink($) {
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
					Prompt => '/[\S\-\_]+[#>]/');
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
		$conn->print($nms::config::tacacs_user);
		my (undef, $match) = $conn->waitfor('/DGS-3100#|Password:/');
		if ($match eq 'Password:') {
			$conn->cmd($nms::config::tacacs_pass);
		}
	}
	return { telnet => $conn };
}

# Send a command to switch and return the data recvied from the switch
sub switch_exec {
	my ($cmd, $conn, $print) = @_;

	sleep 1; # don't overload the D-Link

	# Send the command and get data from switch
	my @data;
	if (defined($print)) {
		$conn->print($cmd);
		return;
	} else {
		@data = $conn->cmd($cmd);
		print "ERROR: " . $conn->errmsg . "\n" if $conn->errmsg;
	}
	return @data;
}

sub switch_exec_json($$) {
	my ($cmd, $conn) = @_;
	my @json = switch_exec("$cmd | display json", $conn);
	pop @json; # Remove the banner at the end of the output
		return ::decode_json(join("", @json));
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
	my ($ip, $community, $async) = @_;

	$async //= 0;

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
		$options{'Community'} = $community;
		$options{'Version'} = 2;
	}

	my $session = SNMP::Session->new(%options);
	if (defined($session) && ($async || defined($session->getnext('sysDescr')))) {
		return $session;
	} else {
		die 'Could not open SNMP session to ' . $ip;
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

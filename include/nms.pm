#! /usr/bin/perl
use strict;
use warnings;
use DBI;
use Net::Telnet;
use Data::Dumper;
use Net::SNMP;
use FileHandle;
package nms;

use base 'Exporter';
our @EXPORT = qw(switch_disconnect switch_connect switch_exec switch_timeout db_connect);

BEGIN {
	require "config.pm";
	eval {
		require "config.local.pm";
	};
}

sub db_connect {
	my $dbh = DBI->connect("dbi:Pg:" .
				"dbname=" . $nms::config::db_name .
				";host=" . $nms::config::db_host,
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

	my $domain = ($ip =~ /:/) ? 'udp6' : 'udp4';
	my $version;
	my %options = (
		-hostname => $ip,
		-domain => $domain,
	);

	if ($community =~ /^snmpv3:(.*)$/) {
		my ($username, $authprotocol, $authpassword, $privprotocol, $privpassword) = split /\//, $1;

		$options{'-username'} = $username;
		$options{'-authprotocol'} = $authprotocol;
		$options{'-authpassword'} = $authpassword;

		if (defined($privprotocol) && defined($privpassword)) {
			$options{'-privprotocol'} = $privprotocol;
			$options{'-privpassword'} = $privpassword;
		}

		$options{'-version'} = 3;
	} else {
		$options{'-version'} = 2;
	}

	my ($session, $error) = Net::SNMP->session(%options);
	die "SNMP session failed: " . $error if (!defined($session));

	return $session;
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

1;

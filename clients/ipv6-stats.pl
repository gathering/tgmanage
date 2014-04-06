#!/usr/bin/perl

use warnings;
use strict;
use lib '../include';
use nms qw(switch_connect switch_exec switch_disconnect);
use Net::Telnet::Cisco;

BEGIN {
        require "../include/config.pm";
        eval {
                require "../include/config.local.pm";
        };
}

#
# Fetch list of MAC addresses and IPv6 addresses
#
sub query_router {
	my ($host) = @_;

	my $ios = Net::Telnet::Cisco->new(
			Host => $host,
			Errmode => 'return');
	if (not defined $ios) {
		warn "Can't connect to $host: $!, skipping";
		return ();
	}
	if (not $ios->login($nms::config::ios_user, $nms::config::ios_pass)) {
		warn "Can't login to $host. Wrong username or password?";
		return ();
	}
	$ios->autopage(0);
	$ios->cmd("terminal length 0");
	my @v6data = $ios->cmd('show ipv6 neighbors')
		or warn "$host wouldn't let me run show ipv6 neighbors.";
	my @v4data = $ios->cmd('show ip arp')
		or warn "$host wouldn't let me run show ip arp.";

	# Remove useless header and footer
#	shift @v6data; 
	pop @v6data;
#	shift @v4data;
	pop @v4data;

	return { 'v6' => \@v6data, 'v4' => \@v4data };
}

while (1) {
	print "Gathering IPv6 and IPv4 stats\n";
	# Connect to DB
	my $dbh = nms::db_connect();
	$dbh->{AutoCommit} = 0;

	my ($v4, $v6) = 0;
	foreach my $router (@nms::config::distrobox_ips) {
		my $data = query_router($router);
		# IPv6
		foreach my $line (@{$data->{'v6'}}) {
			my ($address, $age, $mac, undef, undef) = split('\s+', $line);
			if ($mac =~ /[a-f0-9]{4}\.[a-f0-9]{4}\.[a-f0-9]{4}/ && # Sanity check MAC address
				 $address !~ /^FE.*/) { # Filter out non-routable addresses
				my $q = $dbh->prepare('INSERT INTO ipv6 (address, age, mac, time) VALUES (?, ?, ?, timeofday()::timestamp)')
					or die "Can't prepare query: $!";
				$q->execute($address, $age, $mac)
					or die "Can't execute query: $!";
				$v6++;
			}
		}
		# IPv4
		foreach my $line (@{$data->{'v4'}}) {
			my (undef, $address, $age, $mac, undef, undef) = split('\s+', $line);
			if ($mac =~ /[a-f0-9]{4}\.[a-f0-9]{4}\.[a-f0-9]{4}/) {# Sanity check MAC address
				$age = 0 if $age eq '-';
				my $q = $dbh->prepare('INSERT INTO ipv4 (address, age, mac, time) VALUES (?, ?, ?, timeofday()::timestamp)')
					or die "Can't prepare query: $!";
				$q->execute($address, $age, $mac)
					or die "Can't execute query: $!";
				$v4++;
			}
		}
	}
	print "Added $v6 IPv6 addresses and $v4 IPv4 addresses.\n";
	$dbh->commit;
	$dbh->disconnect;
	
	print "Sleeping for two minutes.\n";
	sleep 120; # Sleep for two minutes
}

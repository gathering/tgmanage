#! /usr/bin/perl

# sesse testing

use strict;
use warnings;
use lib '../include';
use nms;
use Net::CIDR;

my $dbh = nms::db_connect();

my $coregws = $dbh->prepare("SELECT switch, ip, community, sysname FROM switches WHERE switchtype <> 'ex2200'")
	or die "Can't prepare query: $!";
$coregws->execute;

my %switch_id = ();   # sysname -> switch database ID
my %loopbacks = ();   # sysname -> primary address
my %loop_ipv6 = ();   # sysname -> primary address
my %map = ();         # CIDR -> (sysname,ip)*
my %lldpneigh = ();   # sysname -> sysname -> 1

while (my $ref = $coregws->fetchrow_hashref) {
	my $sysname = $ref->{'sysname'};
	$switch_id{$sysname} = $ref->{'switch'};

	print "$sysname...\n";
	my $snmp;
	eval {
		$snmp = nms::snmp_open_session($ref->{'ip'}, $ref->{'community'});
	};
	warn $@ if $@;
	next if not $snmp;

	my $routes = $snmp->gettable('ipCidrRouteTable');
	my $ifs = $snmp->gettable('ifTable');
	my $addrs = $snmp->gettable('ipAddrTable');
	my $lldp = $snmp->gettable('lldpRemTable');
        my $ipaddresstable = $snmp->gettable('ipAddressTable');

	# Find all direct routes we have, and that we also have an address in.
	# These are our linknet candidates.
	for my $route (values %$routes) {
		next if ($route->{'ipCidrRouteMask'} eq '255.255.255.255');
		next if ($route->{'ipCidrRouteNextHop'} ne '0.0.0.0');
		my $cidr = Net::CIDR::addrandmask2cidr($route->{'ipCidrRouteDest'}, $route->{'ipCidrRouteMask'});
		
		for my $addr (values %$addrs) {
			my $ip = $addr->{'ipAdEntAddr'};
			if (Net::CIDR::cidrlookup($ip, $cidr)) {
				push @{$map{$cidr}}, [ $sysname, $ip ];
			}
		}
	}

	# Find the first loopback address.
	my %loopbacks_this_switch = ();
	for my $addr (values %$addrs) {
		my $ifdescr = $ifs->{$addr->{'ipAdEntIfIndex'}}->{'ifDescr'};
		next unless $ifdescr =~ /^Loop/;
		$loopbacks_this_switch{$ifdescr} = $addr->{'ipAdEntAddr'};
	}
	for my $if (sort keys %loopbacks_this_switch) {
		$loopbacks{$sysname} = $loopbacks_this_switch{$if};
		last;
	}

        my %loopbacks_ipv6_this_switch = ();
        for my $addr (values %$ipaddresstable) {
                next if not  $addr->{'ipAddressAddrType'} == 2; # Only IPv6 addresses please.
                my $ifdescr = $ifs->{$addr->{'ipAddressIfIndex'}}->{'ifDescr'};
                next unless $ifdescr =~ /^Loop/;
                $loopbacks_ipv6_this_switch{$ifdescr} = nms::convert_ipv6( $addr->{'ipAddressAddr'} );
        }
        for my $if (sort keys %loopbacks_ipv6_this_switch) {
                $loop_ipv6{$sysname} = $loopbacks_ipv6_this_switch{$if};
                last;
        }

	# Find all LLDP neighbors.
	for my $neigh (values %$lldp) {
		$lldpneigh{lc($sysname)}{lc($neigh->{'lldpRemSysName'})} = 1;
	}
}

# print Dumper(\%switch_id);
# print Dumper(\%map);
# print Dumper(\%loopbacks);
# print Dumper(\%lldpneigh);

$dbh->{AutoCommit} = 0;
$dbh->{RaiseError} = 1;

# Update the switches we have loopback addresses fora
while (my ($sysname, $ip) = each %loopbacks) {
	$dbh->do('UPDATE switches SET ip=? WHERE sysname=?',
		undef, $ip, $sysname);
}
while (my ($sysname, $ipv6) = each %loop_ipv6) {
	$dbh->do('UPDATE switches SET secondary_ip=? WHERE sysname=?',
		undef, $ipv6, $sysname);
}

# Now go through each linknet candidate, and see if we can find any
# direct LLDP neighbors.
my $qexist = $dbh->prepare('SELECT COUNT(*) AS cnt FROM linknets WHERE switch1=? AND switch2=?');
#$dbh->do('DELETE FROM linknets');
while (my ($cidr, $devices) = each %map) {
	for (my $i = 0; $i < scalar @$devices; ++$i) {
		my $device_a = $devices->[$i];
		for (my $j = $i + 1; $j < scalar @$devices; ++$j) {
			my $device_b = $devices->[$j];
			next if $device_a->[0] eq $device_b->[0];
			next unless exists($lldpneigh{lc($device_a->[0])}{lc($device_b->[0])});

			my $switch_a = $switch_id{$device_a->[0]};
			my $switch_b = $switch_id{$device_b->[0]};
			my $ref = $dbh->selectrow_hashref($qexist, undef, $switch_a, $switch_b);
			next if ($ref->{'cnt'} != 0);

			$dbh->do('INSERT INTO linknets (switch1, addr1, switch2, addr2) VALUES (?,?,?,?)',
				undef,
				$switch_a, $device_a->[1],
				$switch_b, $device_b->[1]);
		}
	}
}
$dbh->commit;

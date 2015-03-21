#! /usr/bin/perl
use strict;
use warnings;
use lib '../include';
use nms;
use Data::Validate::IP qw(is_public_ipv6 is_public_ipv4 is_private_ipv4);
use Net::MAC qw(mac_is_unicast);

my $dbh = nms::db_connect();
$dbh->{AutoCommit} = 0;

while (1) {
	my $coregws = $dbh->prepare("SELECT ip, community, sysname FROM switches WHERE switchtype <> 'dlink3100'")
		or die "Can't prepare query: $!";
	$coregws->execute;
	
	my %seen = ();
	my $num_v4 = 0;
	my $num_v6 = 0;
	while (my $ref = $coregws->fetchrow_hashref) {
		print STDERR "Querying ".$ref->{'sysname'}." ...\n";
		my $snmp;
		eval {
			$snmp = nms::snmp_open_session($ref->{'ip'}, $ref->{'community'});
		};
		warn $@ if $@;
		next if not $snmp;
		
		# Pull in old media table that does not support ipv6.
		my $ip_phys_table = fetch($snmp, ('ipNetToMediaNetAddress', 'ipNetToMediaPhysAddress'));
		for my $entry (values %$ip_phys_table) {
			my $ip_addr = $entry->{'ipNetToMediaNetAddress'};
			my $mac = Net::MAC->new(
				mac => nms::convert_mac($entry->{'ipNetToMediaPhysAddress'}),
				die => 0,
			);
		
			next if $mac->get_base() != 16 || $mac->get_mac() eq ''; # We only support base 16 addresses
			next if (!is_public_ipv4($ip_addr) && !is_private_ipv4($ip_addr)); # We consider RFC1918 public
	
			$seen{$ip_addr} = $mac->get_mac();
			$num_v4++;
		}
		
		# Pull in new media table with IPv6 support
		$ip_phys_table = $snmp->gettable('ipNetToPhysicalTable');
		for my $entry (values %$ip_phys_table) {
			my $type = $entry->{'ipNetToPhysicalNetAddressType'};
			my $ip_addr = undef;
			my $mac = Net::MAC->new(
				mac => nms::convert_mac($entry->{'ipNetToPhysicalPhysAddress'}),
				die => 0,
			);
			
			if ($type != 2) {
				warn "$ip_addr is of unexpected type $type (should be 2)! Tell Berge.\n";
				next;
			}
		
			$ip_addr = nms::convert_ipv6($entry->{'ipNetToPhysicalNetAddress'});
		
			next if $mac->get_base() != 16 || $mac->get_mac() eq ''; # We only support base 16 addresses
			next if not is_public_ipv6($ip_addr);
	
			$seen{$ip_addr} = $mac->get_mac();
			$num_v6++;
		}
	
	}
	
	# Populate database
	my $i = 0;
	foreach my $ip_addr (keys %seen) {
		$i++;
		my $q = $dbh->do('INSERT INTO seen_mac (address, mac) VALUES (?, ?)', undef, $ip_addr, $seen{$ip_addr})
			or die "Can't execute query: $!";
	}
	
	$dbh->commit;
	print "Collected $num_v6 IPv6 addresses and $num_v4 IPv4 addresses. $i unique addresses.\n";
	print "Sleeping for 60 seconds ...\n";
	sleep(60);
}


# Fetch provided fields from a single table returning {iid => {tag => val}}
sub fetch {
	my $session = shift;
	my @vars    = map { new SNMP::Varbind([$_]) } @_;
	my $data    = {};
	foreach my $result (@{$session->bulkwalk(0, 8, new SNMP::VarList(@vars))}) {
		foreach my $entry (@$result) {
			$data->{$entry->iid}->{$entry->tag} = $entry->val;
		}
	}
	return $data;
}


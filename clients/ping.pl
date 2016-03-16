#! /usr/bin/perl
use DBI;
use POSIX;
use Time::HiRes;
use Net::Oping;
use strict;
use warnings;

use lib '../include';
use nms;

my $dbh = nms::db_connect();
$dbh->{AutoCommit} = 0;
$dbh->{RaiseError} = 1;

my $q = $dbh->prepare("SELECT switch,ip,secondary_ip FROM switches WHERE ip is not null");
my $lq = $dbh->prepare("SELECT linknet,addr1,addr2 FROM linknets");

while (1) {
	# ping loopbacks
	my $ping = Net::Oping->new;
	$ping->timeout(0.2);

	$q->execute;
	my %ip_to_switch = ();
	my %secondary_ip_to_switch = ();
	while (my $ref = $q->fetchrow_hashref) {
		my $switch = $ref->{'switch'};

		my $ip = $ref->{'ip'};
		$ping->host_add($ip);
		$ip_to_switch{$ip} = $switch;

		my $secondary_ip = $ref->{'secondary_ip'};
		if (defined($secondary_ip)) {
			$ping->host_add($secondary_ip);
			$secondary_ip_to_switch{$secondary_ip} = $switch;
		}
	}
	my $result = $ping->ping();
	die $ping->get_error if (!defined($result));

	$dbh->do('COPY ping (switch, latency_ms) FROM STDIN');  # date is implicitly now.
	while (my ($ip, $latency) = each %$result) {
		my $switch = $ip_to_switch{$ip};
		next if (!defined($switch));

		$latency //= "\\N";
		$dbh->pg_putcopydata("$switch\t$latency\n");
	}
	$dbh->pg_putcopyend();

	$dbh->do('COPY ping_secondary_ip (switch, latency_ms) FROM STDIN');  # date is implicitly now.
	while (my ($ip, $latency) = each %$result) {
		my $switch = $secondary_ip_to_switch{$ip};
		next if (!defined($switch));

		$latency //= "\\N";
		$dbh->pg_putcopydata("$switch\t$latency\n");
	}
	$dbh->pg_putcopyend();

	$dbh->commit;
	# ping linknets
	$ping = Net::Oping->new;
	$ping->timeout(0.2);

	$lq->execute;
	my @linknets = ();
	while (my $ref = $lq->fetchrow_hashref) {
		push @linknets, $ref;
		$ping->host_add($ref->{'addr1'});
		$ping->host_add($ref->{'addr2'});
	}
	if (@linknets) { 
		$result = $ping->ping();
		die $ping->get_error if (!defined($result));

		$dbh->do('COPY linknet_ping (linknet, latency1_ms, latency2_ms) FROM STDIN');  # date is implicitly now.
			for my $linknet (@linknets) {
				my $id = $linknet->{'linknet'};
				my $latency1 = $result->{$linknet->{'addr1'}} // '\N';
				my $latency2 = $result->{$linknet->{'addr2'}} // '\N';
				$dbh->pg_putcopydata("$id\t$latency1\t$latency2\n");
			}
		$dbh->pg_putcopyend();
	}
	$dbh->commit;
}


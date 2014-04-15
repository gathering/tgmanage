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

my $q = $dbh->prepare("SELECT switch,ip FROM switches WHERE ip<>'127.0.0.1'");
my $lq = $dbh->prepare("SELECT linknet,addr1,addr2 FROM linknets");

while (1) {
	# ping loopbacks
	my $ping = Net::Oping->new;
	$ping->timeout(0.2);

	$q->execute;
	my %ip_to_switch = ();
	while (my $ref = $q->fetchrow_hashref) {
		my $switch = $ref->{'switch'};
		my $ip = $ref->{'ip'};
		$ping->host_add($ip);
		$ip_to_switch{$ip} = $switch;
	}
	my $result = $ping->ping();
	die $ping->get_error if (!defined($result));

	$dbh->do('COPY ping (switch, latency_ms) FROM STDIN');  # date is implicitly now.
	while (my ($ip, $latency) = each %$result) {
		my $switch = $ip_to_switch{$ip};
		if (!defined($latency)) {
			$dbh->pg_putcopydata("$switch\t\\N\n");
		} else {
			$dbh->pg_putcopydata("$switch\t$latency\n");
		}
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
	$dbh->commit;
	
	sleep 1;
}


#! /usr/bin/perl
# vim:ts=8:sw=8

use lib '../../include';
use nms::web;
use strict;
use warnings;

my $query = 'select sysname,extract(epoch from date_trunc(\'second\',time)) as time, '.$nms::web::ifname.',ifhighspeed,ifhcinoctets,ifhcoutoctets from polls natural join switches where time in  (select max(time) from polls where ' . $nms::web::when . ' group by switch,ifname);';
my $q = $nms::web::dbh->prepare($query);
$q->execute();

while (my $ref = $q->fetchrow_hashref()) {
 	my @fields = ('ifhcoutoctets','ifhcinoctets');
	foreach my $val (@fields) {
		if ($ref->{'ifname'} =~  /ge-0\/0\/4[4-7]/) {
			$nms::web::json{'switches'}{$ref->{'sysname'}}{'uplinks'}{$val} += $ref->{$val};
		}
		$nms::web::json{'switches'}{$ref->{'sysname'}}{'total'}{$val} += $ref->{$val};
	}
	$nms::web::json{'switches'}{$ref->{'sysname'}}{'time'} += $ref->{'time'};
}

my $q3 = $nms::web::dbh->prepare('select distinct on (switch) switch,temp,time,sysname from switch_temp natural join switches where ' . $nms::web::when . ' order by switch,time desc');

$q3->execute();
while (my $ref = $q3->fetchrow_hashref()) {
	my $sysname = $ref->{'sysname'};
	$nms::web::json{'switches'}{$ref->{'sysname'}}{'temp'} = $ref->{'temp'};
}

my $q2 = $nms::web::dbh->prepare("SELECT DISTINCT ON (sysname) time,sysname, latency_ms FROM ping NATURAL JOIN switches WHERE time in (select max(time) from ping where " . $nms::web::when . " group by switch)");
$q2->execute();
while (my $ref = $q2->fetchrow_hashref()) {
	$nms::web::json{'switches'}{$ref->{'sysname'}}{'latency'} = $ref->{'latency_ms'};
}

my $qs = $nms::web::dbh->prepare("SELECT DISTINCT ON (switch) switch, latency_ms FROM ping_secondary_ip WHERE " . $nms::web::when .  " ORDER BY switch, time DESC;");
$qs->execute();
while (my $ref = $qs->fetchrow_hashref()) {
	$nms::web::json{'switches'}{$ref->{'switch'}}{'latency_secondary'} = $ref->{'latency_ms'};
}

finalize_output();

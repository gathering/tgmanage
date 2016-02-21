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
 	my @fields = ('ifhighspeed','ifhcoutoctets','ifhcinoctets');
	foreach my $val (@fields) {
		$nms::web::json{'switches'}{$ref->{'sysname'}}{'ports'}{$ref->{'ifname'}}{$val} = $ref->{$val};
	}
	$nms::web::json{'switches'}{$ref->{'sysname'}}{'ports'}{$ref->{'ifname'}}{'time'} = $ref->{'time'};
}

my $q3 = $nms::web::dbh->prepare('select distinct on (switch) switch,temp,time,sysname from switch_temp natural join switches where ' . $nms::web::when . ' order by switch,time desc');


$q3->execute();
while (my $ref = $q3->fetchrow_hashref()) {
	my $sysname = $ref->{'sysname'};
	$nms::web::json{'switches'}{$ref->{'sysname'}}{'temp'} = $ref->{'temp'};
	$nms::web::json{'switches'}{$ref->{'sysname'}}{'temp_time'} = $ref->{'time'};
}

finalize_output();

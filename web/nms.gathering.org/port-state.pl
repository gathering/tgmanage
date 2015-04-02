#! /usr/bin/perl
use CGI qw(fatalsToBrowser);
use DBI;
use lib '../../include';
use nms;
use strict;
use warnings;
use Data::Dumper;

my $cgi = CGI->new;

my $dbh = nms::db_connect();

my $switch = $cgi->param('switch');
my @ports = split(",",$cgi->param('ports'));
my @fields = split(",",$cgi->param('fields'));
my $cin = $cgi->param('time');
my $when;
if (!defined($cin)) {
	$when =" time > now() - '5m'::interval";
} else {
	$when = " time < now() - '$cin'::interval and time > now() - ('$cin'::interval + '25m'::interval) ";
}

if (!(@fields)) {
 @fields = ('ifhighspeed','ifhcoutoctets','ifhcinoctets');
}
my $query = 'select distinct on (switch,ifname';
my $val;
foreach $val (@fields) {
	$query .= ",$val";
}
$query .= ') extract(epoch from date_trunc(\'second\',time)) as time,switch,ifname';
foreach $val (@fields) {
	$query .= ",max($val) as $val";
}
$query .= ',switches.sysname from polls2 natural join switches where ' . $when . ' ';
my $or = "and (";
my $last = "";
foreach my $port (@ports) {
	$query .= "$or ifname = '$port' ";
	$or = " OR ";
	$last = ")";
}
$query .= "$last";
if (defined($switch)) {
	$query .= "and sysname = '$switch'";
}
$query .= 'group by time,switch,ifname';
foreach $val (@fields) {
	$query .= ",$val";
}
$query .= ',sysname order by switch,ifname';
foreach $val (@fields) {
	$query .= ",$val";
}
$query .= ',time desc';
my $q = $dbh->prepare($query);
$q->execute();

my %json = ();
while (my $ref = $q->fetchrow_hashref()) {
	foreach $val (@fields) {
		$json{$ref->{'sysname'}}{'ports'}{$ref->{'ifname'}}{$val} = $ref->{$val};
	}
	$json{$ref->{'sysname'}}{'ports'}{$ref->{'ifname'}}{'time'} = $ref->{'time'};
}
#print Dumper(%json);
print $cgi->header(-type=>'text/json; charset=utf-8');
print JSON::XS::encode_json(\%json);

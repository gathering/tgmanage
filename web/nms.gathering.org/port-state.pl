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
my $cin = $cgi->param('time');
my $now = "now()";
if ($cgi->param('now') != undef) {
	$now = "'" . $cgi->param('now') . "'::timestamp ";
}

my $when =" time > " . $now . " - '5m'::interval and time < " . $now . " ";
my %json = ();

if (defined($cin)) {
	$when = " time < " . $now . " - '$cin'::interval and time > ". $now . " - ('$cin'::interval + '5m'::interval) ";
}

my $query = 'select sysname,extract(epoch from date_trunc(\'second\',time)) as time, ifname,ifhighspeed,ifhcinoctets,ifhcoutoctets from polls natural join switches where time in  (select max(time) from polls where ' . $when . ' group by switch,ifname);';
my $q = $dbh->prepare($query);
$q->execute();

while (my $ref = $q->fetchrow_hashref()) {
 	my @fields = ('ifhighspeed','ifhcoutoctets','ifhcinoctets');
	foreach my $val (@fields) {
		$json{'switches'}{$ref->{'sysname'}}{'ports'}{$ref->{'ifname'}}{$val} = $ref->{$val};
	}
	$json{'switches'}{$ref->{'sysname'}}{'ports'}{$ref->{'ifname'}}{'time'} = $ref->{'time'};
}
#print Dumper(%json);

my $q2 = $dbh->prepare('select switch,sysname,placement,ip,switchtype,poll_frequency,community,last_updated from switches natural join placements');
my $q3 = $dbh->prepare('select distinct on (switch) switch,temp,time,sysname from switch_temp natural join switches where ' . $when . ' order by switch,time desc');

$q2->execute();
while (my $ref = $q2->fetchrow_hashref()) {
	$ref->{'placement'} =~ /\((-?\d+),(-?\d+)\),\((-?\d+),(-?\d+)\)/;
	my ($x1, $y1, $x2, $y2) = ($1, $2, $3, $4);
	my $sysname = $ref->{'sysname'};
	$json{'switches'}{$ref->{'sysname'}}{'switchtype'} = $ref->{'switchtype'};
	$json{'switches'}{$ref->{'sysname'}}{'management'}{'ip'} = $ref->{'ip'};
	$json{'switches'}{$ref->{'sysname'}}{'management'}{'poll_frequency'} = $ref->{'poll_frequency'};
	$json{'switches'}{$ref->{'sysname'}}{'management'}{'community'} = $ref->{'community'};
	$json{'switches'}{$ref->{'sysname'}}{'management'}{'last_updated'} = $ref->{'last_updated'};
	$json{'switches'}{$ref->{'sysname'}}{'placement'}{'x'} = $x2;
	$json{'switches'}{$ref->{'sysname'}}{'placement'}{'y'} = $y2;
	$json{'switches'}{$ref->{'sysname'}}{'placement'}{'width'} = $x1 - $x2;
	$json{'switches'}{$ref->{'sysname'}}{'placement'}{'height'} = $y1 - $y2;
}
$q3->execute();
while (my $ref = $q3->fetchrow_hashref()) {
	my $sysname = $ref->{'sysname'};
	$json{'switches'}{$ref->{'sysname'}}{'temp'} = $ref->{'temp'};
	$json{'switches'}{$ref->{'sysname'}}{'temp_time'} = $ref->{'time'};
}

my $q4 = $dbh->prepare(' select linknet, (select sysname from switches where switch = switch1) as sysname1, addr1, (select sysname from switches where switch = switch2) as sysname2,addr2 from linknets');
$q4->execute();
while (my $ref = $q4->fetchrow_hashref()) {
	$json{'linknets'}{$ref->{'linknet'}} = $ref;
#	push @{$json{'linknets'}}, $ref;
}

my $q5;
if (defined($cin)) {
  $q5 = $dbh->prepare ('select (' . $now . ' - \'' .  $cin . '\'::interval) as time;');
} else {
  $q5 = $dbh->prepare ('select ' . $now . ' as time;');
}
$q5->execute();
$json{'time'} = $q5->fetchrow_hashref()->{'time'};

my $q6 = $dbh->prepare('select sysname,extract(epoch from date_trunc(\'second\',time)) as time,state,username,id,comment from switch_comments natural join switches where state != \'delete\' order by time desc');
$q6->execute();
while (my $ref = $q6->fetchrow_hashref()) {
	push @{$json{'switches'}{$ref->{'sysname'}}{'comments'}},$ref;
}

$json{'username'} = $cgi->remote_user();
print $cgi->header(-type=>'text/json; charset=utf-8');
print JSON::XS::encode_json(\%json);

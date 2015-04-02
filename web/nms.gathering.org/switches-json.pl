#! /usr/bin/perl
use CGI;
use GD;
use DBI;
use JSON::XS;
use lib '../../include';
use nms;
my $cgi = CGI->new;

my $dbh = nms::db_connect();
my %json = ();

my $q = $dbh->prepare('select switch,sysname,placement,zorder from switches natural join placements');
my $q2 = $dbh->prepare('select distinct on (switch) switch,temp,time,sysname from switch_temp natural join switches order by switch,time desc');
$q->execute();
while (my $ref = $q->fetchrow_hashref()) {
	$ref->{'placement'} =~ /\((-?\d+),(-?\d+)\),\((-?\d+),(-?\d+)\)/;
	my ($x1, $y1, $x2, $y2) = ($1, $2, $3, $4);
	my $sysname = $ref->{'sysname'};
	$json{'switches'}{$ref->{'switch'}} = {
		sysname => $sysname,
		x => $x2,
		y => $y2,
		width => $x1 - $x2,
		height => $y1 - $y2,
		zorder => $ref->{'zorder'}
	};
}

$q2->execute();
while (my $ref = $q2->fetchrow_hashref()) {
	$json{'switches'}{$ref->{'switch'}}{'temp'} = $ref->{'temp'};
	$json{'switches'}{$ref->{'switch'}}{'time'} = $ref->{'time'};
}
my $q = $dbh->prepare('select linknet,switch1,switch2 from linknets');
$q->execute();
while (my $ref = $q->fetchrow_hashref()) {
	push @{$json{'linknets'}}, $ref;
}

print $cgi->header(-type=>'text/json; charset=utf-8');
print JSON::XS::encode_json(\%json);

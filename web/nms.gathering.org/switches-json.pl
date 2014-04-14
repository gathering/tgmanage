#! /usr/bin/perl
use CGI;
use GD;
use DBI;
use JSON::XS;
use lib '../../include';
use nms;
my $cgi = CGI->new;

my $dbh = nms::db_connect();

my $q = $dbh->prepare('select switch,sysname,placement from switches natural join placements');
$q->execute();

my %json = ();
while (my $ref = $q->fetchrow_hashref()) {
	$ref->{'placement'} =~ /\((-?\d+),(-?\d+)\),\((-?\d+),(-?\d+)\)/;
	my ($x1, $y1, $x2, $y2) = ($1, $2, $3, $4);
	$json{$ref->{'switch'}} = {
		sysname => $ref->{'sysname'},
		x => $x2,
		y => $y2,
		width => $x1 - $x2,
		height => $y1 - $y2
	};
}
print $cgi->header(-type=>'text/json; charset=utf-8');
print JSON::XS::encode_json(\%json);

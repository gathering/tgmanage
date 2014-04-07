#! /usr/bin/perl
use CGI;
use GD;
use DBI;
use JSON::XS;
use lib '../../include';
use nms;
my $cgi = CGI->new;

my $dbh = nms::db_connect();

my $q = $dbh->prepare("SELECT DISTINCT ON (switch) switch, latency_ms FROM ping WHERE updated >= NOW() - INTERVAL '15 secs' ORDER BY switch, updated DESC;");
$q->execute();

my %json = ();
while (my $ref = $q->fetchrow_hashref()) {
	$json{$ref->{'switch'}} = $ref->{'latency_ms'};
}
print $cgi->header(-type=>'text/json; charset=utf-8');
print JSON::XS::encode_json(\%json);

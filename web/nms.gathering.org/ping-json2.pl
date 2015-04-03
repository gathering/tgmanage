#! /usr/bin/perl
use CGI;
use DBI;
use JSON::XS;
use lib '../../include';
use nms;
my $cgi = CGI->new;

my $dbh = nms::db_connect();
my %json = ();

my $q = $dbh->prepare("SELECT DISTINCT ON (switch,sysname) switch,sysname, latency_ms FROM ping NATURAL JOIN switches WHERE updated >= NOW() - INTERVAL '15 secs' ORDER BY switch,sysname, updated DESC;");
$q->execute();
while (my $ref = $q->fetchrow_hashref()) {
	$json{'switches'}{$ref->{'sysname'}}{'latency'} = $ref->{'latency_ms'};
}

my $qs = $dbh->prepare("SELECT DISTINCT ON (switch) switch, latency_ms FROM ping_secondary_ip WHERE updated >= NOW() - INTERVAL '15 secs' ORDER BY switch, updated DESC;");
$qs->execute();
while (my $ref = $qs->fetchrow_hashref()) {
	$json{'switches'}{$ref->{'switch'}}{'latency_secondary'} = $ref->{'latency_ms'};
}

my $lq = $dbh->prepare("SELECT DISTINCT ON (linknet) linknet, latency1_ms, latency2_ms FROM linknet_ping WHERE updated >= NOW() - INTERVAL '15 secs' ORDER BY linknet, updated DESC;");
$lq->execute();
while (my $ref = $lq->fetchrow_hashref()) {
	$json{'linknets'}{$ref->{'linknet'}} = [ $ref->{'latency1_ms'}, $ref->{'latency2_ms'} ];
}

$q->execute();
print $cgi->header(-type=>'text/json; charset=utf-8');
print JSON::XS::encode_json(\%json);

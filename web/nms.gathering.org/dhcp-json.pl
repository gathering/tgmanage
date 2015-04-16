#! /usr/bin/perl
use CGI qw(fatalsToBrowser);
use DBI;
use lib '../../include';
use nms;
my $cgi = CGI->new;

my $dbh = nms::db_connect();

my $q = $dbh->prepare('select sysname,EXTRACT(EPOCH FROM last_ack) as last_ack from switches natural join dhcp ');
$q->execute();

my %json = ();
while (my $ref = $q->fetchrow_hashref()) {
	$json{'dhcp'}{$ref->{'sysname'}}{'last_ack'} = $ref->{'last_ack'};
}
$dbh->disconnect;
print $cgi->header(-type=>'text/json; charset=utf-8');
print JSON::XS::encode_json(\%json);

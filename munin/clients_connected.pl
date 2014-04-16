#! /usr/bin/perl -I/root/tgmanage/include
use strict;
use warnings;
use lib 'include';
use nms;
use Data::Dumper::Simple;

my $dbh = nms::db_connect();
$dbh->{AutoCommit} = 0;

my $active_clients = $dbh->prepare("select family(address), count(distinct(mac)) from seen_mac where family(address) in (6,4) and  seen >= now() - INTERVAL '1 hour' group by family(address);")
	or die "Can't prepare query: $!";

$active_clients->execute;
print <<EOF;
graph_title Clients seen the last hour
graph_vlabel count
graph_scale no
EOF
while (my $ref = $active_clients->fetchrow_hashref) {
  print "clients_".$ref->{'family'}.".label v".$ref->{'family'}." clients\n";
  print "clients_".$ref->{'family'}.".value ".$ref->{'count'}."\n";
}
$active_clients->finish;
$dbh->disconnect();
exit 0

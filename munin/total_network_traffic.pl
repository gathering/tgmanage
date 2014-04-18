#! /usr/bin/perl -I/root/tgmanage/include
use strict;
use warnings;
use lib 'include';
use nms;
use Data::Dumper::Simple;

# By the looks of this code, the in/out values are from the perspective of the
# switch. However, something gets flipped somewhere which makes it from the
# perspective of the client. I have no idea why. Have fun!

my $dbh = nms::db_connect();
$dbh->{AutoCommit} = 0;

my $total_traffic = $dbh->prepare("select sum(bytes_in) * 8 / 1048576.0 / 1024.0 as traffic_in, sum(bytes_out) * 8 / 1048576.0 / 1024.0 as traffic_out from get_current_datarate() natural join switches where switchtype like 'dlink3100%' and port < 45")
	or die "Can't prepare query: $!";

$total_traffic->execute;
print <<EOF;
graph_title Total network traffic
graph_vlabel Gb/s
graph_scale no
EOF
my $ref = $total_traffic->fetchrow_hashref;
print "total_network_traffic_in.label Total incoming traffic\n";
print "total_network_traffic_in.value ". $ref->{'traffic_in'}."\n";
print "total_network_traffic_out.label Total outgoing traffic\n";
print "total_network_traffic_out.value ". $ref->{'traffic_out'}."\n";
$total_traffic->finish;
$dbh->disconnect();
exit 0;

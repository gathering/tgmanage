#! /usr/bin/perl -I/root/tgmanage/include
use strict;
use warnings;
use lib 'include';
use nms;
use Data::Dumper::Simple;

my $dbh = nms::db_connect();
$dbh->{AutoCommit} = 0;

# D-Links
my $sth = $dbh->prepare("select sum(bytes_in) * 8 / 1048576.0 / 1024.0 as traffic_in, sum(bytes_out) * 8 / 1048576.0 / 1024.0 as traffic_out from get_current_datarate() natural join switches where switchtype like 'dlink3100%' and port < 45")
        or die "Can't prepare query: $!";
$sth->execute();
my $total_traffic_dlink = $sth->fetchrow_hashref();
$sth->finish();

# TeleGW
$sth = $dbh->prepare("select sum(bytes_in) * 8 / 1048576.0 / 1024.0 as traffic_in, sum(bytes_out) * 8 / 1048576.0 / 1024.0 as traffic_out from get_current_datarate() natural join switches where sysname like '%TeleGW%' and (port=64 or port=65 or port=69 or port=70)")
	or die "Can't prepare query: $!";
$sth->execute();
my $total_traffic_telegw = $sth->fetchrow_hashref();
$sth->finish();

$dbh->disconnect();

my $total = $total_traffic_dlink->{'traffic_in'} + $total_traffic_dlink->{'traffic_out'};
$total += $total_traffic_telegw->{'traffic_in'} + $total_traffic_telegw->{'traffic_out'};

# Now we have summarized in+out for clients and in+out for internet-traffic
# We divide by two to get an average
$total = $total / 2;
my $nicetotal = sprintf ("%.2f", $total);

# {"speed":19.12}
print qq({"speed":$nicetotal});
exit 0

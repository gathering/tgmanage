#! /usr/bin/perl
use strict;
use DBI;
use lib '../../include';
use nms;
use CGI;
use File::Basename;
my $cwd = dirname($0);
my $dbh = nms::db_connect();

my $cgi = CGI->new;

print $cgi->header(-type=>'text/json', -expires=>'now');

my $q = $dbh->prepare('select sum(n1.sum_in) as sum_in, sum(n1.sum_out) as sum_out from (select sum(ifInoctets) as sum_in, sum(ifOutoctets) as sum_out from polls2 where time >= now() - \'15 minutes\'::interval group by switch) as n1');
$q->execute();
while (my $ref = $q->fetchrow_hashref()) {
    my $bitsface = $ref->{'sum_in'}/900/8;
    
    print <<"EOF";
{
  "sum_in": "$bitsface"
}
EOF
}

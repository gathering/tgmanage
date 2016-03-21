#! /usr/bin/perl
use CGI;
use GD;
use DBI;
use lib '../../include';
use nms;
my $cgi = CGI->new;

my $dbh = nms::db_connect();

print $cgi->header(-type=>'text/plain', -expires=>'now');

my $q = $dbh->prepare('select * from ( SELECT switch,sysname,sum(bytes_in) AS bytes_in,sum(bytes_out) AS bytes_out from switches natural left join get_current_datarate() group by switch,sysname) t1 natural join placements order by zorder;');
$q->execute();
while (my $ref = $q->fetchrow_hashref()) {
	my $sysname = $ref->{'sysname'};
	next unless $sysname =~ /e\d+-\d+/;
	printf "%s %s\n", $sysname, (defined($ref->{'bytes_in'}) ? 'on' : 'off');
}
$dbh->disconnect;

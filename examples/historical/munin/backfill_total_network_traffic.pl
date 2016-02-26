#! /usr/bin/perl -I/root/tgmanage/include
use strict;
use warnings;
use lib 'include';
use nms;
use Data::Dumper::Simple;

use Date::Parse;

my $dbh = nms::db_connect();
$dbh->{AutoCommit} = 0;

# This has a slightly modded version of get_current_datarate inlined. It's probably outdated by the time you read this.
my $total_traffic = $dbh->prepare("select sum(bytes_in) * 8 / 1048576.0 / 1024.0 as traffic_out, sum(bytes_out) * 8 / 1048576.0 / 1024.0 as traffic_in from (SELECT switch,port,
      (bytes_out[1] - bytes_out[2]) / EXTRACT(EPOCH FROM (time[1] - time[2])) AS bytes_out,
      (bytes_in[1] - bytes_in[2]) / EXTRACT(EPOCH FROM (time[1] - time[2])) AS bytes_in,
      time[1] AS last_poll_time
      FROM (
        SELECT switch,port,
        ARRAY_AGG(time) AS time,
        ARRAY_AGG(bytes_in) AS bytes_in,
        ARRAY_AGG(bytes_out) AS bytes_out
        FROM (
           SELECT *,rank() OVER (PARTITION BY switch,port ORDER BY time DESC) AS poll_num
           FROM polls WHERE time BETWEEN (to_timestamp(?) - interval '5 minutes') AND to_timestamp(?)
           AND official_port
        ) t1
        WHERE poll_num <= 2
        GROUP BY switch,port
      ) t2
      WHERE
        time[2] IS NOT NULL
        AND bytes_in[1] >= 0 AND bytes_out[1] >= 0
        AND bytes_in[2] >= 0 AND bytes_out[2] >= 0
        AND bytes_out[1] >= bytes_out[2]
        AND bytes_in[1] >= bytes_in[2]) as datarate natural join switches where switchtype like 'dlink3100%' and port < 45")
	or die "Can't prepare query: $!";

my $inout = shift @ARGV;
while (<>) {
	if (m,<!-- [^/]* CEST / (\d+) --> <row><v>[^<]*</v></row>, && $1 > 1397458800) {
		my $time = $1;
		if ($time > 1397458800) {
			$total_traffic->execute($time, $time);
			my $ref = $total_traffic->fetchrow_hashref;
			my $value = $ref->{'traffic_' . $inout};
			$value = (!defined $value || $value == 0 || $value > 400) ? "NaN" : sprintf "%e", $value;
			s,<v>[^<]*</v>,<v>$value</v>,;		
		}
	}
	print;
}
$total_traffic->finish;
$dbh->disconnect();
exit 0

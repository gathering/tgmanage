#! /usr/bin/perl
use CGI;
use DBI;
use lib '../../include';
use nms;
my $cgi = CGI->new;

my $dbh = nms::db_connect();
print $cgi->header(-type=>'text/html; charset=utf-8', -refresh=>'10; ' . CGI::url());

print <<"EOF";
<html>
  <head>
    <title>nettkart</title>
  </head>
  <body>
    <map name="switches">
EOF

my $q = $dbh->prepare("select * from switches natural join placements where ip <> inet '127.0.0.1'");
$q->execute();
while (my $ref = $q->fetchrow_hashref()) {
	$ref->{'placement'} =~ /\((\d+),(\d+)\),\((\d+),(\d+)\)/;
	
	my $traffic = 4.0 * $ref->{'bytes_in'} + $ref->{'bytes_out'};  # average and convert to bits (should be about the same in practice)
	my $ttext;
	if ($traffic >= 1_000_000_000) {
		$ttext = sprintf "%.2f Gbit/port/sec", $traffic/1_000_000_000;
	} elsif ($traffic => 1_000_000) {
		$ttext = sprintf "%.2f Mbit/port/sec", $traffic/1_000_000;
	} else {
		$ttext = sprintf "%.2f kbit/port/sec", $traffic/1_000;
	}

	printf "      <area shape=\"rect\" coords=\"%u,%u,%u,%u\" href=\"showswitch.pl?id=%u\" alt=\"%s (%s)\" onmouseover=\"window.status='%s (%s)'; return true\" onmouseout=\"window.status=''\" />\n",
		$3, $4, $1, $2, $ref->{'switch'}, $ref->{'sysname'},
		$ttext, $ref->{'sysname'}, $ttext;
}
$dbh->disconnect;

print <<"EOF";
    </map>

    <p><img src="nettkart.pl" usemap="#switches" /></p>
  </body>
</html>
EOF

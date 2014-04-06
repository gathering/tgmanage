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
    <title>Uplinkkart</title>
  </head>
  <body>
    <map name="switches">
EOF

my $q = $dbh->prepare("SELECT * FROM switches NATURAL JOIN placements WHERE switchtype = 'dlink3100'");
$q->execute();
while (my $ref = $q->fetchrow_hashref()) {
	$ref->{'placement'} =~ /\((\d+),(\d+)\),\((\d+),(\d+)\)/;
	
	my $ttext = 'FIXME: Put something here';
	printf "      <area shape=\"rect\" coords=\"%u,%u,%u,%u\" href=\"switchdiag.pl?id=%u\" alt=\"%s (%s)\" onmouseover=\"window.status='%s (%s)'; return true\" onmouseout=\"window.status=''\" />\n",
		$3, $4, $1, $2, $ref->{'switch'}, $ref->{'sysname'},
		$ttext, $ref->{'sysname'}, $ttext;
}
$dbh->disconnect;

print <<"EOF";
    </map>

    <p><img src="uplinkkart.pl" usemap="#switches" /></p>
  </body>
</html>
EOF

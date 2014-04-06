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
    <title>MBD status</title>
  </head>
  <body>
    <h1>MBD status</h1>

    <p>Spill søkt etter siste 15 minutter:</p>

    <table>
      <tr>
        <th>Beskrivelse</th>
	<th>Aktive servere</th>
      </tr>
EOF

my $q = $dbh->prepare('select description,sum(active_servers) as active_servers from (select distinct on (game,port) * from mbd_log where ts >= now() - \'10 minutes\'::interval order by game,port,ts desc ) t1 group by description order by sum(active_servers) desc, description;');
$q->execute();
while (my $ref = $q->fetchrow_hashref()) {
	print <<"EOF";
      <tr>
        <td>$ref->{'description'}</td>
	<td>$ref->{'active_servers'}</td>
      </tr>
EOF
}
$dbh->disconnect;

print <<"EOF";
    </table>
  </body>
</html>
EOF

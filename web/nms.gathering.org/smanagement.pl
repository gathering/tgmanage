#!/usr/bin/perl
use warnings;
use strict;
use 5.010;
use CGI;
use DBI;
use Data::Dumper;
use lib '../../include';
use nms;

# Grab from .htaccess-authentication
my $user = $ENV{'REMOTE_USER'};

my $dbh = nms::db_connect();
$dbh->{AutoCommit} = 0;

# Ugly casting, found no other way
my $sinsert = $dbh->prepare(	"INSERT INTO squeue 
				(gid, added, priority, addr, sysname, cmd, author)
				VALUES(?::text::int, timeofday()::timestamptz, ?::text::int, ?::text::inet, ?, ?, ?)")
	or die "Could not prepare sinsert";
my $sgetip = $dbh->prepare("SELECT ip FROM switches WHERE sysname = ?")
	or die "Could not prepare sgetip";
my $sgid = $dbh->prepare("SELECT nextval('squeue_group_sequence') as gid");
my $all_switches = $dbh->prepare("SELECT sysname FROM switches ORDER BY sysname");

sub parse_range($) {
	my $switches = $_;
	my @range;

	my @rangecomma = split(/\s*,\s*/, $switches);
	foreach (@rangecomma) {
		my ($first, $last) = $_ =~ /(e\d+\-(?:sw)?[123456])\s*\-\s*(e\d+\-(?:sw)?[123456])?/;
		if (!defined($first) && $_ =~ /e\d+\-(sw)?[123456]/) {
			$first = $_;
		}
		if (!defined($first)) {
			print "<font color=\"red\">Parse error in: $_</font><br>\n";
			next;
		}
		my ($rowstart, $placestart) = $first =~ /e(\d+)\-(?:sw)?([123456])/;
		if (!defined($rowstart) || !defined($placestart)) {
			print "<font color=\"red\">Parse error in: $_</font><br>\n";
			next;
		}
		my ($rowend, $placeend);
		if (!defined($last)) {
			$rowend = $rowstart;
			$placeend = $placestart;
		}
		else {
			($rowend, $placeend) = $last =~ /e(\d+)\-(?:sw)?([123456])/;
		}
		if (!defined($rowend) || !defined($placeend)) {
			print "<font color=\"red\">Parse error in: $_</font><br>\n";
			next;
		}
		#print "e $rowstart - $placestart to e $rowend - $placeend <br>\n";
		for (my $i = $rowstart; $i <= $rowend; $i++) {
			my $dostart;
			if ($rowstart != $i) {
				$dostart = 1;
			}
			else {
				$dostart = $placestart;
			}
			for (my $j = $dostart; $j <= 6; $j++) {
				last if ($i == $rowend && $j > $placeend);
				push(@range, "e$i-$j");
			}
		}
	}
#	foreach (@range) {
#		print ":: $_<br>\n";
#	}
	return @range;
}

sub get_addr_from_switchnum($) {
	my ($sysname) = @_;

	$sgetip->execute($sysname);
	if ($sgetip->rows() < 1) {
		print "Could not get the ip for: ".$sysname;
		return undef;
	}
	my $row = $sgetip->fetchrow_hashref();
	return $row->{'ip'};
}

my $cgi = new CGI;

print $cgi->header(-type=>'text/html; charset=utf-8');

print << "EOF";
<html>
  <head>
    <title>Switch managment</title>
  </head>
  <body>
  <p>Du er logget inn som: $user</p>
    <form method="POST" action="smanagement.pl">
    <table>
      <tr>
        <td>Alle switchene</td>
        <td><input type="radio" name="rangetype" value="all" /></td>
	<td></td>
	<td></td>
      </tr>
      <tr>
        <td>Switch</td>
        <td><input type="radio" checked name="rangetype" value="switch" /></td>
        <td><input type="text" name="range" /></td>
        <td>e1-2, e3-3 - e10-2</td>
      </tr>
      <tr>
        <td>Regexp</td>
        <td><input type="radio" name="rangetype" value="regexp" /></td>
        <td><input type="text" name="regexp" /></td>
        <td>Regulært uttrykk</td>
      </tr>
      <tr>
        <td>Rad</td>
        <td><input type="radio" name="rangetype" value="row" /></td>
        <td><input type="text" name="range" /></td>
        <td>1,3-5 (Disabled)</td>
      </tr>
       <tr>
        <td><hr /></td>
        <td><hr /></td>
        <td><hr /></td>
        <td><hr /></td>
      </tr>
      <tr>
	<td>Prioritet</td>
	<td></td>
	<td>
	  <select name="priority">
	    <option value="1">1 (lavest)</option>
	    <option value="2">2</option>
	    <option selected value="3">3</option>
	    <option value="4">4</option>
	    <option value="5">5 (høyest)</option>
	  </select>
	</td>
      </tr>
      <tr>
        <td>Kommando(er):</td>
        <td></td>
	<td><textarea name="cmd" cols="80" rows="24"></textarea></td>
	<td>En kommando per linje. Linjer som begynner med ! sørger for at nms ikke venter på normal prompt, men fyrer av gårde neste linje umiddelbart. Kjekt for kommandoer av typen "!save\\nY"</td>
      </td>
      <tr>
        <td><hr /></td>
        <td><hr /></td>
        <td><hr /></td>
        <td><hr /></td>
      </tr>
    </table>
    <input type="submit" value="Execute!" /><br />
    </form>
EOF

print "<br />\n";

my @switches = ();
given ($cgi->param('rangetype')) {
	when ('all') {
		print "Sender `".$cgi->param('cmd')."` til alle switchene<br />";
		@switches = ();
		$all_switches->execute();
		while (my $ref = $all_switches->fetchrow_hashref) {
			push @switches, $ref->{'sysname'};
		}
	}
	when ('switch') {
#		print "Sender `".$cgi->param('cmd')."` til switchene `"
#		      .$cgi->param('range')."`.<br />";
		$_ = $cgi->param('range');
		@switches = parse_range($_);
	}
	when ('regexp') {
		@switches = ();
		$all_switches->execute();
		while (my $ref = $all_switches->fetchrow_hashref) {
			push @switches, $ref->{'sysname'} if $ref->{'sysname'} =~ $cgi->param('regexp');
		}
	}
	when ('row') {
#		print "Sender `".$cgi->param('cmd')."` til radene `"
#		      .$cgi->param('range')."`.<br />";
#		print "This function does not work yet.";
#		$_ = $cgi->param('range');
#		@switches = &parse_row_range($_);
#		@switches = ();
		print "<font color=\"red\">Slått av!</font>\n";
	}
};

my $gid;
if (@switches > 0) {
	$sgid->execute();
	my $row = $sgid->fetchrow_hashref();
	$gid = $row->{gid};
}

my $pri = $cgi->param('priority');

print "<pre>\n";
foreach my $switch (@switches) {
	my $addr = get_addr_from_switchnum($switch);
	if (!defined($addr)) {
		next;
	}
	my $cmd = $cgi->param('cmd');
	print "$switch got addr $addr <br>\n";
	print "Queuing commands for $switch:\n";
	my $result = $sinsert->execute($gid, $pri, $addr, $switch, $cmd, $user);
	if (!$result) {
		print "\t<font color=\"red\">"
		       ."Could not execute query."
		       ."</font>\n";
		print "\t".$dbh->errstr."\n";
	}
	else {
		print "\tQueued: $cmd\n";
	}
	print "\n";
}
$dbh->commit;
if (defined($gid)) {
	print "<a href=\"sshow.pl?action=showgid&gid=".$gid."\">Vis resultat</a>\n";
}
print "</pre>\n";

print << "EOF";
  </body>
</html>
EOF

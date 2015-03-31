#!/usr/bin/perl
use lib '../../include';
use nms;

use warnings;
use strict;
use Switch;
use CGI;
use DBI;
use HTML::Entities;

# Grab from .htaccess-authentication
my $user = $ENV{'REMOTE_USER'};

my $dbh = nms::db_connect();
$dbh->{AutoCommit} = 0;

my $sgetdone = $dbh->prepare(
"SELECT * 
FROM  squeue 
WHERE processed = 't' 
ORDER BY updated DESC, sysname
LIMIT ?::text::int")
	or die "Could not prepare sgetdone";

my $sgetdonegid = $dbh->prepare(
"SELECT * 
FROM  squeue 
WHERE processed = 't' AND gid = ?::text::int 
ORDER BY updated DESC, sysname")
	or die "Could not prepare sgetdonegid";

my $slistdonegid = $dbh->prepare(
"SELECT DISTINCT gid, cmd, author, added
FROM squeue
WHERE processed = 't'
ORDER BY gid")
	or die "Could not prepare slistdonegid";

my $slistprocgid = $dbh->prepare(
"SELECT DISTINCT gid, cmd, author, added
FROM squeue
WHERE processed = 'f'
ORDER BY gid")
	or die "Could not prepare slistdonegid";

my $sgetgid = $dbh->prepare(
"SELECT *
FROM squeue
WHERE gid = ?")
	or die "Could not prepare sgetgid";

my $sgetprocessing = $dbh->prepare(
"SELECT *
FROM  squeue
WHERE processed = 'f'
ORDER BY updated DESC, gid, sysname")
	or die "Could not prepare sgetdone";

my $sgetnoconnect = $dbh->prepare(
"SELECT *
FROM squeue
WHERE result = 'Could not connect to switch, delaying...'")
	or die "Could not prepare sgetnoconnect";

my $sdisablegid = $dbh->prepare("
UPDATE squeue SET disabled = 't'
WHERE gid = ?::text::int")
	or die "Could not prepare sdisablegid";
my $senablegid = $dbh->prepare("
UPDATE squeue SET disabled = 'f'
WHERE gid = ?::text::int")
	or die "Could not prepare sdisablegid";


my $cgi = new CGI;

print $cgi->header(-type=>'text/html; charset=utf-8');

print << "EOF";
<html>
  <head>
    <title>Switch managment</title>
  </head>
  <body>
  <p>Du er logget inn som: $user</p>
    <form method="POST" action="sshow.pl">
    <p>
      Vis <input type="text" name="count" size="4" value="10" /> siste<br />
      Vis: <select name="action" />
       <option value="listgid">Grupper</option>
       <option value="done">Ferdige</option>
       <option value="processing">I kø</option>
      </select>
      <input type="submit" value="Vis" /><br />
    </p>
    </form>
    <br />
EOF

my $limit = $cgi->param('count');
if (!defined($limit)) {
	$limit = 10;
}
my $action = $cgi->param('action');
if (!defined($action)) {
	$action = 'listgid';
}

if (defined($cgi->param('agid'))) {
	my $gid = $cgi->param('gid');
	if (!defined($gid)) {
		print "<font color=\"red\">Du har ikke valgt en gid å slette.</font>\n";
		print "<p>gid: ".$cgi->param('gid')." har blitt disablet.\n";
	}
	else {
		$senablegid->execute($gid);
		print "<p>gid: ".$cgi->param('gid')." har blitt enablet.\n";
	}
	$dbh->commit();
}

if ($action eq 'noconnect') {
	print "<h3>Kunne ikke koble til disse switchene:</h3>\n";
	$sgetnoconnect->execute();
	print "<pre>\n";
	while ((my $row = $sgetnoconnect->fetchrow_hashref())) {
		print "$row->{'sysname'} : $row->{'cmd'} : Added: $row->{'added'} : Updated: $row->{'updated'}\n";
	}
	print "</pre>\n";
}

if ($action eq 'listgid') {
	print "<pre>\n";
	print "<a href=\"sshow.pl?action=noconnect\" />Kunne ikke koble til</a>\n\n\n";
	print "<b>Ferdige:</b>\n";
	$slistdonegid->execute();
	my ($gid, $author);
	$gid = -1;
	while ((my $row = $slistdonegid->fetchrow_hashref())) {
		$author = $row->{author};
		if ($gid != $row->{gid}) {
			$gid = $row->{gid};
			print "GID: <a href=\"sshow.pl?action=showgid&gid=$gid\">$gid</a>\n";
			print "Author: $author\n";
			print "Added: ".$row->{added}."\n";
		}
		my $cmd = $row->{cmd};
		print "\t$cmd\n";
	}
	print "\n\n";
	print "<b>I kø:</b>\n";
	$slistprocgid->execute();
	$gid = -1;
	while ((my $row = $slistprocgid->fetchrow_hashref())) {
		$author = $row->{author};
		if ($gid != $row->{gid}) {
			$gid = $row->{gid};
			print "GID: <a href=\"sshow.pl?action=showgid&gid=$gid\">$gid</a>\n";
			print "Author: $author\n";
			print "Added: ".$row->{added}."\n";
		}
		my $cmd = $row->{cmd};
		print "\t$cmd\n";
	}
	$dbh->commit();
	print "</pre>\n";
}

if ($action eq 'showgid') {
	print "<pre>\n";
	$sgetgid->execute($cgi->param('gid'));
	my $row = $sgetgid->fetchrow_hashref();
	print "GID: ".$row->{gid}."\n";
	print "Author: ".$row->{author}."\n";
	do {
		print "    <b>Name: ".$row->{sysname}." Addr: ".$row->{addr}."</b>\n";
		print "    `<b>".$row->{cmd}."`</b>\n";
		print "    <i>Added: ".$row->{added}." executed ".$row->{updated}."</i>\n";
		my $data = $row->{result};
		if (!defined($data)) {
			$data = "Not executed yet!";
		}
		my @lines = split(/[\n\r]+/, $data);
		foreach my $line (@lines) {
			print "\t", encode_entities($line), "\n";
		}
	} while (($row = $sgetgid->fetchrow_hashref()));
	print "</pre>\n";
}

if ($action eq 'done') {
	print "<h3>Done</h3>\n";
	print "<pre>\n";

	my $squery;
	if (defined($cgi->param('gid'))) {
		my $gid = $cgi->param('gid');
		$sgetdonegid->execute($gid);
		$squery = $sgetdonegid;
	}
	else {
		$sgetdone->execute($limit);
		$squery = $sgetdone;
	}
	my $sysname = '';
	while (my $row = $squery->fetchrow_hashref()) {
		if ($sysname ne $row->{'sysname'}) {
			$sysname = $row->{'sysname'};
			print "$sysname (".$row->{addr}."):\n";
		}
		print "   Author: ".$row->{author}."\n";
		print "   Cmd: ".$row->{cmd}."\n";
		print "   Added: ".$row->{added}." Updated: ".$row->{updated}."\n";
		print "   gID: ".$row->{gid}."\n";
		my @result = split(/[\n\r]+/, $row->{result});
		foreach (@result) {
			print "\t", encode_entities($_), "\n";
		}
		print "\n";
	}
	$dbh->commit();
	print "</pre>\n";
}
elsif ($action eq 'processing') {
	print "<h3>Processing</h3>\n";
	print "<pre>\n";
	$sgetprocessing->execute();
	while (my $row = $sgetprocessing->fetchrow_hashref()) {
		my $sysname = $row->{'sysname'};
		print "$sysname (".$row->{addr}."):\n";
		print "   Author: ".$row->{author}."\n";
		print "   Cmd: ".$row->{cmd}."\n";
		my $updated;
		if (defined($row->{updated})) { $updated = $row->{updated}; }
		else { $updated = 'never'; }
		print "   Added: ".$row->{added}." Updated: ".$updated."\n";
		print "   Disabled: ".$row->{disabled}."\n";
		print "   Locked: ".$row->{locked}."\n";
		print "   gID: ".$row->{gid};
		print "   <form action=\"sshow.pl\" methos=\"POST\">";
		print "<input type=\"hidden\" name=\"gid\" value=\"".$row->{gid}."\">";
		print "<input type=\"hidden\" name=\"action\" value=\"processing\">";
		if ($row->{disabled} == 0) {
			print "<input type=\"submit\" name=\"agid\" value=\"Disable\">\n";
		}
		else {
			print "<input type=\"submit\" name=\"agid\" value=\"Enable\">\n";
		}
	}
	$dbh->commit();
	print "</pre>\n";
}

print << "EOF";
  </body>
</html>
EOF

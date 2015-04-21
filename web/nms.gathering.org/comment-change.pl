#! /usr/bin/perl
use CGI qw(fatalsToBrowser);
use DBI;
use lib '../../include';
use utf8;
use nms;
use strict;
use warnings;
use Data::Dumper;

my $cgi = CGI->new;

my $dbh = nms::db_connect();

my $id = $dbh->quote($cgi->param('comment') || die );
my $state= $dbh->quote($cgi->param('state') || die);


my $q = $dbh->prepare("UPDATE switch_comments SET state = " . $state . " WHERE id = " . $id . ";");
$q->execute();

print $cgi->header(-type=>'text/json; charset=utf-8');
print "{ 'state': 'ok' }";


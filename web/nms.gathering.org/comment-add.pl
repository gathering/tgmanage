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

my $data = $dbh->quote($cgi->param('comment') || die );
my $switch = $dbh->quote($cgi->param('switch') || die );
my $user = $dbh->quote($cgi->remote_user() || "undefined");


my $q = $dbh->prepare("INSERT INTO switch_comments (time,username,switch,comment) values (now(),$user,(select switch from switches where sysname = $switch limit 1),$data)");
$q->execute();

print $cgi->header(-type=>'text/json; charset=utf-8');
print "{ 'state': 'ok' }";


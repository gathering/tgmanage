#! /usr/bin/perl
use CGI;
use GD;
use DBI;
use lib '../../include';
use nms;
my $cgi = CGI->new;

my $dbh = nms::db_connect();
my $box = sprintf("(%d,%d)", $cgi->param('x'), $cgi->param('y'));

$dbh->do('UPDATE placements SET placement=box(?::point, ?::point + point(width(placement),height(placement))) WHERE switch=?',
	undef, $box, $box, $cgi->param('switch'));
print $cgi->header(-type=>'text/plain', -expires=>'now');


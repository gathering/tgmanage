#! /usr/bin/perl

# Make the given switch into a D-Link placement-wise.

use strict;
use warnings;
use lib '../include';
use nms;

my $dbh = nms::db_connect();
my $q = $dbh->prepare('SELECT switch,placement FROM switches NATURAL JOIN placements WHERE sysname LIKE ?');
$q->execute('%'.$ARGV[0].'%');

while (my $ref = $q->fetchrow_hashref) {
	$ref->{'placement'} =~ /\((\d+),(\d+)\),\((\d+),(\d+)\)/ or die;
	my ($x1,$y1,$x2,$y2) = ($1, $2, $3, $4);
	my $placement = sprintf "(%d,%d),(%d,%d)", $x2 - 100, $y2 - 16, $x2, $y2;
	$dbh->do("UPDATE placements SET placement=? WHERE switch=?",
		undef, $placement, $ref->{'switch'});
	last;  # Take only one.
}

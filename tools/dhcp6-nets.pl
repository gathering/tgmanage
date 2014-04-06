#!/usr/bin/perl
use strict;
use warnings;

while(<STDIN>){
	my ($row, $v6) = split;
	$v6 =~ s/::1/::/;

	print "subnet6 $v6 {\n";
	print "\toption domain-name \"$row.tg13.gathering.org\";\n";
	print "}\n\n";
}

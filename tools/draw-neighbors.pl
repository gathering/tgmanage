#!/usr/bin/perl

use strict;
use JSON;

my $in;
while (<STDIN>) {
	$in .= $_;
}

my %assets = %{JSON::XS::decode_json($in)};

print "Drawing family tree from JSON:\n\n";
while (my ($key, $value) = each %assets) {
	print_tree ($key,0,undef);
	last;
}
sub print_tree
{
	my ($chassis_id,$indent,$parent,$max) = @_;
	if (!defined($parent)) {
		$parent = "";
	}
	if ($indent > 50) {
		die "Possible loop detected.";
	}
	for (my $i = 0; $i < $indent; $i++) {
		print "\t";
	}
	print " - " . $assets{$chassis_id}{sysName} . "\n";
	while (my ($key, $value) = each %{$assets{$chassis_id}{neighbors}}) {
		if ($key ne $parent) {
			print_tree($key,$indent+1,$chassis_id);
		}
	}
}

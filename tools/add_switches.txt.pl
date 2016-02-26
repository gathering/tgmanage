#!/usr/bin/perl
# Usage: ./add_switches.txt.pl < switches.txt > switches.json
# 
# Parses switches.txt into json and does some guesswork for placement based
# on name, if possible.
#
# Actually adding them comes later.
#

use strict;
use warnings;
use Data::Dumper;

my %switches = ();

# Guesses placement from name to get a starting point
# Largely courtesy of Knuta
sub guess_placement {
	my ($x, $y, $xx, $yy);

	my $name = $_[0];
	my $src = "unknown";
	if ($name =~ /^e\d+-\d+$/) {
		$name =~ /e(\d+)-(\d+)/;
		my ($e, $s) = ($1, $2);
		$src = "main";

		$x = int(232 + (($e-1)/2) * 31.1);
		$y = undef;

		$x += 14 if ($e >= 17);
		$x += 14 if ($e >= 29);
		$x += 14 if ($e >= 45);
		$x += 14 if ($e >= 63);

		if ($s > 2) {
			$y = 405 - 120 * ($s-2);
		} else {
			$y = 689 - 120 * ($s);
		}

		$xx = $x + 16;
		$yy = $y + 120;

		# Justeringer
		$y += 45 if $name eq "e1-4";
		$y += 20 if $name eq "e3-4";
		$y += 15 if $name eq "e5-4";
		$yy -= 25 if $name eq "e11-1";

		#$yy -= 14 if $name eq "e77-1";
		#$yy -= 28 if $name eq "e79-1";
		#$yy -= 15 if $name eq "e81-1";
		#$yy -= 56 if $name eq "e83-1";
	} elsif ($name =~ /^sw(\d+)-creativia$/) {
		my ($s) = ($1);
		$src = "creativia";
		$x = 1535;
		$y = int(130 + 32.2 * $s);
		$yy = $y + 20;
		if ($s == 1) {
			$xx = $x + 70;
		} elsif ($s == 2) {
			$xx = $x + 90;
		} elsif ($s == 3) {
			$xx = $x + 102;
		} else {
			$xx = $x + 142;
		}

	} elsif ($name =~ /^crew(\d+)-(\d+)$/) {
		my ($s, $n) = ($1, $2);
		$src = "crew";
		$x = 1023 + 45 * $n;
		$y = int(329 + 20.5 * $s);
		$xx = $x + 45;
		$yy = $y + 14;

		if ($s == 1 && $n == 1) {
			$xx += 25;
		}
	} else {
		# Fallback to have _some_ position
		$src = "random";
		$x = int(rand(500));
		$y = int(rand(500));
		$xx = $x + 20;
		$yy = $y + 130;
	};


	my %box = (
		'src' => "$src",
		'x1' => $x,
		'y1' => $y,
		'xx' => $xx,
		'yy' => $yy
	);
	return %box;
}
while (<STDIN>) {
	chomp;
	my ($switch, $subnet4, $subnet6, $mgtmt4, $mgtmt6, $lolid, $distro) = split(/ /);
	my %foo = guess_placement($switch);
	$switches{$switch} = {
		'subnet4' => "$subnet4",
		'subnet6' => "$subnet6",
		'mgtmt4' => "$mgtmt4",
		'mgtmt6' => "$mgtmt6",
		'lolid' => "$lolid",
		'distro' => "$distro"
	};
	$switches{$switch}{'placement_guess'} = \%foo;
}

print Dumper(\%switches);

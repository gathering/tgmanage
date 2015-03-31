#! /usr/bin/perl
use strict;
use warnings;

my $switchtype = "ex2200";

print "begin;\n";
print "delete from placements where switch in (select switch from switches where switchtype = '$switchtype');\n";

my %ip;
my $i = 1;
while (<STDIN>) {
	chomp;
	my @info = split(/ /);

	if (scalar @info < 5) {
		die "Unknown line: $_";
	}
	my ($x, $y, $xx, $yy);

	my $name = $info[0];
	if ($name =~ /^e\d+-\d+$/) {
		$name =~ /e(\d+)-(\d+)/;
		my ($e, $s) = ($1, $2);

		$x = int(205 + (($e-1)/2) * 20.2);
		$y = undef;

		$x += 8 if ($e >= 11);
		$x += 6 if ($e >= 27);
		$x += 12 if ($e >= 43);
		$x += 7 if ($e >= 60);

		if ($s > 2) {
			$y = 328 - 84 * ($s-2);
		} else {
			$y = 519 - 84 * ($s);
		}

		$xx = $x + 14;
		$yy = $y + 84;

		# Justeringer
		$y += 45 if $name eq "e1-4";
		$y += 20 if $name eq "e3-4";
		$y += 15 if $name eq "e5-4";

		#$yy -= 14 if $name eq "e77-1";
		#$yy -= 28 if $name eq "e79-1";
		$yy -= 15 if $name eq "e81-1";
		#$yy -= 56 if $name eq "e83-1";
	} elsif ($name =~ /^creative(\d+)-(\d+)$/) {
		my ($s, $n) = ($1, $2);
		$x = 973 + 52 * $n;
		$y = int(138 + 22.2 * $s);
		$xx = $x + 52;
		$yy = $y + 14;

		if ($s == 2 && $n == 1) {
			$xx += 10;
		}
		if ($s == 3 && $n == 1) {
			$xx += 20;
		}
	} elsif ($name =~ /^crew(\d+)-(\d+)$/) {
		my ($s, $n) = ($1, $2);
		$x = 1023 + 45 * $n;
		$y = int(329 + 20.5 * $s);
		$xx = $x + 45;
		$yy = $y + 14;

		if ($s == 1 && $n == 1) {
			$xx += 25;
		}
	} else {
		die "Unknown switch: $name";
	}

	print "insert into placements select switch, box '(($x,$y),($xx,$yy))' from switches where sysname = '$name';\n";
	$i++;
}

print "end;\n";

#! /usr/bin/perl
use strict;
use warnings;

my $switchtype = "ex2200";

print "begin;\n";
print "delete from placements where switch in (select switch from switches where switchtype = '$switchtype' and (sysname like 'e%') or sysname like '%creativia%');\n";

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
		$x = 1023 + 45 * $n;
		$y = int(329 + 20.5 * $s);
		$xx = $x + 45;
		$yy = $y + 14;

		if ($s == 1 && $n == 1) {
			$xx += 25;
		}
	} else {
		next;
	}

	print "insert into placements select switch, box '(($x,$y),($xx,$yy))' from switches where sysname = '$name';\n";
	$i++;
}

print "end;\n";

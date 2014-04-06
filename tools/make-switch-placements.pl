#! /usr/bin/perl
use strict;
use warnings;

my $switchtype = "dlink3100";

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

		$x = int(220 + (($e-1)/2) * 21.5);
		$y = undef;

		$x += 10 if ($e >= 11);
		$x += 10 if ($e >= 27);
		$x += 10 if ($e >= 43);
		$x += 10 if ($e >= 59);

		if ($s > 2) {
			$y = 310 - 84 * ($s-2);
		} else {
			$y = 507 - 84 * ($s);
		}

		$xx = $x + 14;
		$yy = $y + 84;

		# Justeringer
		$y += 42 if $name eq "e1-4";
		$y += 28 if $name eq "e3-4";
		$y += 14 if $name eq "e5-4";

		$yy -= 14 if $name eq "e77-1";
		$yy -= 28 if $name eq "e79-1";
		$yy -= 42 if $name eq "e81-1";
		$yy -= 56 if $name eq "e83-1";
	} elsif ($name =~ /^creative(\d+)$/) {
		my $s = $1;
		if ($s < 3) {
			if ($s == 1) {
				$x = 1190;
				$y = 278;
			} else {
				$x = 1180;
				$y = 230;
			}
			$xx = $x+35;
			$yy = $y+19;
			$yy += 6;
		} else {
			$x = 1056;
			$y = 296 - 22 * ($s-3);
			if ($s <= 4) {
				$xx = $x+100;
			} elsif ($s <= 7) {
				$xx = $x+70;
			} elsif ($s <= 8) {
				$xx = $x+55;
			} else {
				$xx = $x+35;
			}
			$yy = $y+19;
			$yy -= 5 if $s == 3;
		}
	} else {
		die "Unknown switch: $name";
	}

	print "insert into placements select switch, box '(($x,$y),($xx,$yy))' from switches where sysname = '$name';\n";
	$i++;
}

print "end;\n";

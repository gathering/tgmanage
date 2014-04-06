#! /usr/bin/perl

print "begin;\n";
print "delete from placements;\n";

open PATCHLIST, "../patchlist.txt"
	or die "../patchlist.txt: $!";

my $RANGE = "87.76.";

my $i = 1;
while (<PATCHLIST>) {
	chomp;
	my ($name, $distro, $port) = split / /;

	$name =~ /e(\d+)-(\d+)/;
	my ($e, $s) = ($1, $2);

	my $x = int(168 + $e * 11);
	my $y;

	$x += 1  if ($e >= 11);
	$x += 2  if ($e >= 15);
	$x += 2  if ($e >= 15 && $e < 45 && $s > 2);
	$x += 2  if ($e >= 21);
	$x += 2  if ($e >= 27 && $e < 45 && $s > 2);
	$x += 9  if ($e >= 29);
	$x += 1  if ($e >= 31);
	$x += 2  if ($e >= 35);
	$x += 15 if ($e >= 45);
	$x += 2  if ($e >= 51);
	$x += 11 if ($e >= 61);
	$x += 1  if ($e >= 67);
	$x += 1  if ($e >= 71);
	$x += 1  if ($e >= 75);
	$x += 1  if ($e >= 81);

	if ($s > 2) {
		$y = 152 + 88 - 88 * ($s-3);
	} else {
		$y = 357 + 88 - 88 * ($s-1);
	}

	my $xx = $x + 16;
	my $yy = $y + 88;

	# Justeringer

	print "insert into placements (switch, placement) values ($i, box '(($x,$y),($xx,$yy))');\n";
	$i++;
}

print "end;\n";

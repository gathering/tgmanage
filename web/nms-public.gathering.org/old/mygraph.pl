#! /usr/bin/perl -T
use strict;
use warnings;
use GD;
use POSIX;
use Time::Zone;

sub blendpx {
	my ($gd, $x, $y, $r, $g, $b, $frac) = @_;
	my ($ro, $go, $bo) = $gd->rgb($gd->getPixel($x, $y));

	# workaround for icky 256-color graphs
	# $frac = int($frac * 32) / 32;

	my $rn = $ro * (1.0 - $frac) + $r * $frac;
	my $gn = $go * (1.0 - $frac) + $g * $frac;
	my $bn = $bo * (1.0 - $frac) + $b * $frac;

	$gd->setPixel($x, $y, $gd->colorResolve($rn, $gn, $bn));
}

# Standard implementation of Wu's antialiased line algorithm.
sub wuline {
	my ($gd, $x1, $y1, $x2, $y2, $r, $g, $b, $a) = @_;
	$x1 = POSIX::floor($x1);
	$x2 = POSIX::floor($x2);
	$y1 = POSIX::floor($y1);
	$y2 = POSIX::floor($y2);

	if (abs($x2 - $x1) > abs($y2 - $y1)) {
		# x-directional
		if ($y2 < $y1) {
			($x2, $y2, $x1, $y1) = ($x1, $y1, $x2, $y2);
		}

		my $y = POSIX::floor($y1);
		my $frac = $y1 - $y;
		my $dx = ($x2 > $x1) ? 1 : -1;
		my $dy = ($y2 - $y1) / abs($x2 - $x1);

		for (my $x = $x1; $x != $x2 + $dx; $x += $dx) {
			blendpx($gd, $x, $y, $r, $g, $b, $a * (1.0 - $frac));
			blendpx($gd, $x, $y + 1, $r, $g, $b, $a * $frac);
			$frac += $dy;
			if ($frac > 1) {
				$frac -= 1;
				++$y;
			}
		}
	} else {
		# y-directional
		if ($x2 < $x1) {
			($x2, $y2, $x1, $y1) = ($x1, $y1, $x2, $y2);
		}
		my $x = POSIX::floor($x1);
		my $frac = $x1 - $x;
		my $dy = ($y2 > $y1) ? 1 : -1;
		my $dx = ($x2 - $x1) / abs($y2 - $y1);

		for (my $y = $y1; $y != $y2 + $dy; $y += $dy) {
			blendpx($gd, $x, $y, $r, $g, $b, $a * (1.0 - $frac));
			blendpx($gd, $x + 1, $y, $r, $g, $b, $a * $frac);
			$frac += $dx;
			if ($frac > 1) {
				$frac -= 1;
				++$x;
			}
		}
	}
}

sub makegraph {
	my $xoffset = 70;
	my ($width, $height, $min_x, $max_x, $min_y, $max_y, $tickgran) = @_;

	# Create our base graph
	my $graph = new GD::Image($width, $height, 1);
	my $white = $graph->colorAllocate(255, 255, 255);
	my $gray = $graph->colorAllocate(230, 230, 255);
	my $black = $graph->colorAllocate(0, 0, 0);

#	$graph->fill(0, 0, $white);
	$graph->filledRectangle(0, 0, $width, $height, $white); # seems to work better

	$::xs = ($width - ($xoffset+2)) / ($max_x - $min_x);
	$::ys = ($height - 33) / ($min_y - $max_y);
	
	# Hour marks
	for my $i ($xoffset+1..$width-2) {
		if (((($i-($xoffset+1)) / $::xs + $min_x) / 3600) % 2 == 1) {
			$graph->line($i, 0, $i, $height - 1, $gray);
		}
	}

	# Hour text
	for my $i (0..23) {
		my @bounds = GD::Image::stringFT(undef, $black, "/usr/share/fonts/truetype/msttcorefonts/Arial.ttf", 10, 0, 0, 0, $i);
		my $w = $bounds[2] - $bounds[0];

		# Determine where the center of this will be
		my $starthour = POSIX::fmod(($min_x + Time::Zone::tz_local_offset()) / 3600, 24);
		my $diff = POSIX::fmod($i - $starthour + 24, 24);

		my $center = ($diff * 3600 + 1800) * $::xs;

		next if ($center - $w / 2 < 1 || $center + $w / 2 > $width - ($xoffset+2));
		$graph->stringFT($black, "/usr/share/fonts/truetype/msttcorefonts/Arial.ttf", 10, 0, $xoffset + $center - $w / 2, $height - 6, $i);
	}

	#
	# Y lines; we want max 11 of them (zero-line, plus five on each side, or
	# whatever) but we don't want the ticks to be on minimum 50 (or
	# whatever $tickgran is set to). However, if there would be
	# really really few lines, go down an order of magnitude and try
	# again.
	# 
	my $ytick;
	do {
		$ytick = ($max_y - $min_y) / 11;
		$ytick = POSIX::ceil($ytick / $tickgran) * $tickgran;
		$tickgran *= 0.1; 
	} while (($max_y - $min_y) / $ytick < 4);

	for my $i (-11..11) {
		my $y = ($i * $ytick - $max_y) * $::ys + 10;
		next if ($y < 2 || $y > $height - 18);

		if ($i == 0) {
			wuline($graph, $xoffset, $y, $width - 1, $y, 0, 0, 0, 1.0);
			wuline($graph, $xoffset, $y + 1, $width - 1, $y + 1, 0, 0, 0, 1.0);
		} else {
			wuline($graph, $xoffset, $y, $width - 1, $y, 0, 0, 0, 0.2);
		}

		# text
		my $traf = 8 * ($i * $ytick);
		my $text;
		if ($traf >= 500_000_000) {
			$text = (sprintf "%.1f Gbit", ($traf/1_000_000_000));
		} elsif ($traf >= 500_000) {
			$text = (sprintf "%.1f Mbit", ($traf/1_000_000));
		} else {
			$text = (sprintf "%.1f kbit", ($traf/1_000));
		}
		
		my @bounds = GD::Image::stringFT(undef, $black, "/usr/share/fonts/truetype/msttcorefonts/Arial.ttf", 10, 0, 0, 0, $text);
		my $w = $bounds[2] - $bounds[0];
		my $h = $bounds[1] - $bounds[5];

		next if ($y - $h/2 < 2 || $y + $h/2 > $height - 12);
		$graph->stringFT($black, "/usr/share/fonts/truetype/msttcorefonts/Arial.ttf", 10, 0, ($xoffset - 4) - $w, $y + $h/2, $text);
	}

	# Nice border(TM)
	$graph->rectangle($xoffset, 0, $width - 1, $height - 1, $black);

	return $graph;
}

sub plotseries {
	my ($graph, $xvals, $yvals, $r, $g, $b, $min_x, $max_y) = @_;
	my $xoffset = 70;

	my @xvals = @{$xvals};
	my @yvals = @{$yvals};

	my $x = $xvals[0];
	my $y = $yvals[0];
	for my $i (1..$#xvals) {
		next if ($::xs * ($xvals[$i] - $x) < 2 && $::ys * ($yvals[$i] - $y) > -2); 

		wuline($graph, ($x-$min_x) * $::xs + $xoffset + 1, ($y-$max_y) * $::ys + 10,
				($xvals[$i]-$min_x) * $::xs + $xoffset + 1, ($yvals[$i]-$max_y) * $::ys + 10, $r, $g, $b, 1.0);
		$x = $xvals[$i];
		$y = $yvals[$i];
	}
}

1;

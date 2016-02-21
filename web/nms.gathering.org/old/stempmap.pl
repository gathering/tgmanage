#!/usr/bin/perl
#
#
use strict;
use warnings;

use CGI;
use GD;
use DBI;
use File::Basename;
use lib '../../include';
use nms;

GD::Image->trueColor(1);

my $cwd = dirname($0);
my $img = GD::Image->new($cwd.'/tg15-salkart.png');
my $cgi = CGI->new;

my $dbh = nms::db_connect();

my $max_update_age = '\'8 min\'::interval';

# Henter ut de som er oppdatert for mindre enn $max_update_age siden
my $sgetpoll = $dbh->prepare('select switch,sysname,(select temp from switch_temp where switches.switch = switch_temp.switch AND temp != 0 order by time desc limit 1) AS temp,placement from switches natural join placements where now()-'.$max_update_age.' < last_updated');

my $black = $img->colorAllocate(0,0,0);
my $white = $img->colorAllocate(255,255,255);
my $grey  = $img->colorAllocate(192,192,192);
my $green = $img->colorAllocate(0,255,0);
my $blue = $img->colorAllocate(0,0,255);

my $mintemp = 10.0;
my $maxtemp = 55.0;
my $steps = 100;

for (my $i = 0; $i < $steps; $i++) {
	my $diff = $maxtemp - $mintemp;
	my $temp = $mintemp + ($maxtemp - $mintemp) * ((($diff / $steps) * $i)/$diff);
	$img->line(5, $i, 45, $i, &getcolor($temp));
}

$img->stringFT($black, "/usr/share/fonts/truetype/msttcorefonts/Arial.ttf", 10, 0, 50, 10, "Freezing!");
$img->stringFT($black, "/usr/share/fonts/truetype/msttcorefonts/Arial.ttf", 10, 0, 50, 22, "$mintemp C");
$img->stringFT($black, "/usr/share/fonts/truetype/msttcorefonts/Arial.ttf", 10, 0, 50, $steps - 12, "$maxtemp C");
$img->stringFT($black, "/usr/share/fonts/truetype/msttcorefonts/Arial.ttf", 10, 0, 50, $steps, "Too hot!");

$sgetpoll->execute();
while (my $ref = $sgetpoll->fetchrow_hashref()) {
	next if (!defined($ref->{'temp'}));

	my $sysname = $ref->{'sysname'};
	$sysname =~ s/sw$//;

	my $temp = $ref->{'temp'};
	my $color = getcolor($temp);

	$ref->{'placement'} =~ /\((\d+),(\d+)\),\((\d+),(\d+)\)/;
	my ($x2, $y2, $x1, $y1) = ($1, $2, $3, $4);
	$img->filledRectangle($x1,$y1,$x2,$y2,$color);
	$img->rectangle($x1,$y1,$x2,$y2,$black);
	my $max_textlen = ($x2-$x1) > ($y2-$y1) ? $x2-$x1 : $y2-$y1;
	while (length($sysname) * 6 > $max_textlen) {
		# Try to abbreviate sysname if it is too long for the box
		$sysname =~ s/^(.*)[a-z]~?([0-9-]+)$/$1~$2/ or last;
	}
	if (($x2-$x1) > ($y2-$y1)) {
		$img->string(gdSmallFont,$x1+2,$y1,$sysname,$white);
	} else {
		$img->stringUp(gdSmallFont,$x1,$y2-3,$sysname,$white);
	}
	$img->string(gdGiantFont, $x2-(length("$temp") * 9), $y1, "$temp", $white);
}

print $cgi->header(-type=>'image/png');
print $img->png;

sub getcolor {
	my ($temp) = @_;

	my $t = ($temp - $mintemp) / ($maxtemp - $mintemp);
	$t = 0 if ($t < 0);
	$t = 1 if ($t > 1);

	my $colorred = 65025 * $t;
	my $colorblue = 65025 - $colorred;

	return $img->colorResolve(sqrt($colorred), 0, sqrt($colorblue) );
}

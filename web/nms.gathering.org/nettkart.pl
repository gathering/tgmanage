#! /usr/bin/perl
use CGI;
use GD;
use Image::Magick;
use DBI;
use lib '../../include';
use strict;
use warnings;
use nms;
use File::Basename;
my $cgi = CGI->new;
my $cwd = dirname($0);

# Sekrit night-mode
my $night = defined($cgi->param('night'));

my $dbh = nms::db_connect();

GD::Image->trueColor(1);

my $text_img;
our $img = GD::Image->new($cwd.'/tg15-salkart.png');
if ($night) {
	my ($width, $height) = ($img->width, $img->height); 

	$img = GD::Image->new($width, $height, 1);
	$img->alphaBlending(0);
	$img->saveAlpha(1);
	my $blank = $img->colorAllocateAlpha(0, 0, 0, 127);
	$img->filledRectangle(0, 0, $img->width - 1, $img->height - 1, $blank);

	$text_img = GD::Image->new($width, $height, 1);
	$text_img->alphaBlending(0);
	$text_img->saveAlpha(1);
	$blank = $text_img->colorAllocateAlpha(0, 0, 0, 127);
	$text_img->filledRectangle(0, 0, $text_img->width - 1, $text_img->height - 1, $blank);
} else {
	$text_img = $img;
}

my $blk = $img->colorResolve(0, 0, 0);

for my $y (42..236) {
	my $i = 4.0 * ($y - 236.0) / (42.0 - 237.0);
	my $clr = get_color($i);
	
	$img->filledRectangle(12, $y, 33, $y+1, $clr);
	$text_img->filledRectangle(12, $y, 33, $y+1, $clr);
}

$text_img->rectangle(12,42,33,236,$blk);

my $tclr = $night ? $text_img->colorResolve(255, 255, 255) : $blk;
$text_img->stringFT($tclr, "/usr/share/fonts/truetype/msttcorefonts/Arial.ttf", 10, 0, 40, 47 + (236-42)*0.0/4.0, "100 Gbit/sec");
$text_img->stringFT($tclr, "/usr/share/fonts/truetype/msttcorefonts/Arial.ttf", 10, 0, 40, 47 + (236-42)*1.0/4.0, "10 Gbit/sec");
$text_img->stringFT($tclr, "/usr/share/fonts/truetype/msttcorefonts/Arial.ttf", 10, 0, 40, 47 + (236-42)*2.0/4.0, "1 Gbit/sec");
$text_img->stringFT($tclr, "/usr/share/fonts/truetype/msttcorefonts/Arial.ttf", 10, 0, 40, 47 + (236-42)*3.0/4.0, "100 Mbit/sec");
$text_img->stringFT($tclr, "/usr/share/fonts/truetype/msttcorefonts/Arial.ttf", 10, 0, 40, 47 + (236-42)*4.0/4.0, "10 Mbit/sec");
$text_img->stringFT($tclr, "/usr/share/fonts/truetype/msttcorefonts/Arial.ttf", 10, 0, 1600, 1000, "NMS (C) 2005-2012 Tech:Server");

my $q = $dbh->prepare("select * from ( SELECT switch,sysname,sum(bytes_in) AS bytes_in,sum(bytes_out) AS bytes_out from switches natural left join get_current_datarate() where ip <> inet '127.0.0.1' group by switch,sysname) t1 natural join placements order by zorder;");
$q->execute();
while (my $ref = $q->fetchrow_hashref()) {

	# for now:
	# 10Mbit/switch = green
	# 100Mbit/switch = yellow
	# 1Gbit/switch = red
	# 10Gbit/switch = white
	
	my $clr;

	if (defined($ref->{'bytes_in'})) {
		my $intensity = 0.0;
		my $traffic = 4.0 * ($ref->{'bytes_in'} + $ref->{'bytes_out'});  # average and convert to bits (should be about the same in practice)

		my $max = 100_000_000_000.0;   # 100Gbit
		my $min =      10_000_000.0;   # 10Mbit
		if ($traffic >= $min) {
			$intensity = log($traffic / $min) / log(10);
			$intensity = 4.0 if ($intensity > 4.0);
		}
		$clr = get_color($intensity);
	} else {
		$clr = $img->colorResolve(0, 0, 255);
	}
	
	my $sysname = $ref->{'sysname'};
	$sysname =~ s/-sekrit//;
	
	$ref->{'placement'} =~ /\((\d+),(\d+)\),\((\d+),(\d+)\)/;
	$img->filledRectangle($3,$4,$1,$2,$clr);
	$text_img->filledRectangle($3,$4,$1,$2,$clr);

	$img->rectangle($3,$4,$1,$2,$blk);
	$text_img->rectangle($3,$4,$1,$2,$blk);
	my ($x2, $y2, $x1, $y1) = ($1, $2, $3, $4);
	my $max_textlen = ($x2-$x1) > ($y2-$y1) ? $x2-$x1 : $y2-$y1;
	while (length($sysname) * 6 > $max_textlen) {
		# Try to abbreviate sysname if it is too long for the box
		$sysname =~ s/^(.*)[a-z]~?([0-9-]+)$/$1~$2/ or last;
	}
	if (($x2-$x1) > ($y2-$y1)) {
		$text_img->string(gdSmallFont,$x1+2,$y1,$sysname,$blk);
	} else {
		$text_img->stringUp(gdSmallFont,$x1,$y2-3,$sysname,$blk);
	}
}
$dbh->disconnect;

print $cgi->header(-type=>'image/png', -expires=>'now');
if ($night) {
	my $magick = Image::Magick->new;
	$magick->BlobToImage($img->png);
	$magick->Blur(sigma=>10.0, channel=>'All');
	$magick->Gamma(gamma=>1.90);

	my $m2 = Image::Magick->new;
	$m2->Read($cwd.'/tg15-salkart.png');
	$m2->Negate();
	$m2->Composite(image=>$magick, compose=>'Atop');

	my $m3 = Image::Magick->new;
	$m3->BlobToImage($text_img->png);
	$m2->Composite(image=>$m3, compose=>'Atop');
	
	$img = $m2->ImageToBlob();
	print $img;
} else {	
	print $img->png;
}

sub get_color {
	my $intensity = shift;
	my $gamma = 1.0/1.90;
	if ($intensity > 3.0) {
		return $img->colorResolve(255.0 * ((4.0 - $intensity) ** $gamma), 255.0 * ((4.0 - $intensity) ** $gamma), 255.0 * ((4.0 - $intensity) ** $gamma));
	} elsif ($intensity > 2.0) {
		return $img->colorResolve(255.0, 255.0 * (($intensity - 2.0) ** $gamma), 255.0 * (($intensity - 2.0) ** $gamma));
	} elsif ($intensity > 1.0) {
		return $img->colorResolve(255.0, 255.0 * ((2.0 - $intensity) ** $gamma), 0);
	} else {
		return $img->colorResolve(255.0 * ($intensity ** $gamma), 255, 0);
	}
}

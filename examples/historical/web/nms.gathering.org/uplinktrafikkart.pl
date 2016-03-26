#! /usr/bin/perl
use CGI qw(fatalsToBrowser);
use GD;
use DBI;
use lib '../../include';
use nms;
use strict;
use warnings;
use File::Basename;
my $cgi = CGI->new;
my $cwd = dirname($0);

#my $greentimeout = 7200;
my $greentimeout = 15*60;
my $maxtimeout = $greentimeout*9;

my $dbh = nms::db_connect();

GD::Image->trueColor(1);
my $img = GD::Image->new($cwd.'/tg15-salkart.png');

my $blk = $img->colorResolve(0, 0, 0);

for my $y (42..236) {
	my $i = 2.0 * ($y - 236.0) / (42.0 - 237.0);
	my $clr = get_color($i);
	
	$img->filledRectangle(12, $y, 33, $y+1, $clr);
}

$img->string(gdMediumBoldFont,0,0,"Switch uplink traffic",$blk);
$img->string(gdSmallFont,0,20,"max of bytes in/out",$blk);

my $red = $img->colorResolve(255, 0, 0);
my $yel = $img->colorResolve(255, 255, 0);
my $grn = $img->colorResolve(0, 255, 0);
my $wht = $img->colorResolve(255, 255, 255);

$img->rectangle(12,42,33,236,$blk);

$img->stringFT($blk, "/usr/share/fonts/truetype/msttcorefonts/Arial.ttf", 10, 0, 40, 47 + (236-42)*0.0/2.0, "4 Gbit/sec");
$img->stringFT($blk, "/usr/share/fonts/truetype/msttcorefonts/Arial.ttf", 10, 0, 40, 47 + (236-42)*1.0/2.0, "2 Gbit/sec");
$img->stringFT($blk, "/usr/share/fonts/truetype/msttcorefonts/Arial.ttf", 10, 0, 40, 47 + (236-42)*2.0/2.0, "1 Gbit/sec");
$img->stringFT($blk, "/usr/share/fonts/truetype/msttcorefonts/Arial.ttf", 10, 0, 1600, 1000, "NMS (C) 2005-2012 Tech:Server");

my $q = $dbh->prepare('select switch,sysname,(select placement from placements where placements.switch=switches.switch) as placement,greatest(sum(bytes_in),sum(bytes_out)) as traffic from switches natural left join get_current_datarate() natural join placements where port between 45 and 48 and switchtype like \'dlink3100%\' group by switch,sysname');
$q->execute();
while (my $ref = $q->fetchrow_hashref()) {
	my $traffic = $ref->{'traffic'} * 8.0;  # convert to bits
	my $sysname = $ref->{'sysname'};

	my $max = 4_000_000_000.0;   # 2Gbit
	my $min = 1_000_000_000.0;   # 1Gbit
	$traffic = $max if ($traffic > $max);
	$traffic = $min if ($traffic < $min);
	my $intensity = log($traffic / $min) / log(2);
	my $clr = get_color($intensity);
	
	$ref->{'placement'} =~ /\((\d+),(\d+)\),\((\d+),(\d+)\)/;
	$img->filledRectangle($3,$4,$1,$2,$clr);
	$img->rectangle($3,$4,$1,$2,$blk);

	my ($x2, $y2, $x1, $y1) = ($1, $2, $3, $4);
	my $max_textlen = ($x2-$x1) > ($y2-$y1) ? $x2-$x1 : $y2-$y1;
	while (length($sysname) * 6 > $max_textlen) {
		# Try to abbreviate sysname if it is too long for the box
		$sysname =~ s/^(.*)[a-z]~?([0-9]+)$/$1~$2/ or last;
	}
	if (($x2-$x1) > ($y2-$y1)) {
		$img->string(gdSmallFont,$x1+2,$y1,$sysname,$blk);
	} else {
		$img->stringUp(gdSmallFont,$x1,$y2-3,$sysname,$blk);
	}
}
$dbh->disconnect;

if (!defined($ARGV[0])) {
	print $cgi->header(-type=>'image/png',
			   -refresh=>'10; ' . CGI::url());
}
print $img->png;

sub get_color {
	my $intensity = shift;
	my $gamma = 1.0/1.90;
	if ($intensity > 1.0) {
		$intensity -= 1.0;
		return $img->colorResolve(255.0, 255.0 * ($intensity ** $gamma), 255.0 * ($intensity ** $gamma));
	} else {
		return $img->colorResolve(255.0 * ($intensity ** $gamma), 255.0 * (1.0 - ($intensity ** $gamma)), 0);
	}
}

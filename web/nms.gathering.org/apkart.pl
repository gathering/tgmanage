#! /usr/bin/perl
use CGI qw(fatalsToBrowser);
use GD;
use DBI;
use lib '../../include';
use nms;
use strict;
use warnings;
my $cgi = CGI->new;

#my $greentimeout = 7200;
my $greentimeout = 15*60;
my $maxtimeout = $greentimeout*9;

my $dbh = nms::db_connect();

GD::Image->trueColor(1);

my $img = GD::Image->new('tg14-salkart.png');

my $blk = $img->colorResolve(0, 0, 0);
my $red = $img->colorResolve(255, 0, 0);
my $grn = $img->colorResolve(0, 255, 0);
my $blu = $img->colorResolve(0, 0, 255);

# Her ska' det bættre skrivas STORT jah!
my $title = new GD::Image(75,15);
$img->alphaBlending(1);
$title->alphaBlending(1);
my $titlebg = $title->colorResolve(255, 255, 255);
$title->fill(0,0,$titlebg);
$title->transparent($titlebg);
$title->string(gdGiantFont,7,0,"APEKART",$title->colorResolve(255, 0, 0));
$img->copyResampled($title, 500, 0, 0, 0, 400, 100, 75, 15);
$img->copyResampled($title, 500, 550, 0, 0, 400, 100, 75, 15);

$img->string(gdMediumBoldFont,0,0,"Access points",$blk);
$img->string(gdSmallFont,0,20,"Shows if a Cisco access point is plugged into the port",$blk);

my %palette = ( 'notpolled' => $blu, 'missing' => $red, 'present' => $grn );

my @states = qw(present missing notpolled);

for my $i (0..$#states) {
	my $y = 60 + 20 * (4 - $i);
	$img->filledRectangle(20, $y, 30, $y + 10, $palette{$states[$i]});
	$img->rectangle(20, $y, 30, $y + 10, $blk);
	$img->stringFT($blk, "/usr/share/fonts/truetype/msttcorefonts/Arial.ttf", 10, 0, 40, $y + 10, $states[$i]);
}

my $q = $dbh->prepare("select switch,sysname,model,last_poll < now() - '30 seconds'::interval as notpolled,placement from switches natural join placements natural join ap_poll order by zorder");
$q->execute();
while (my $ref = $q->fetchrow_hashref()) {
	my $sysname = $ref->{'sysname'};
	my $model = $ref->{'model'};
	my $state;
	if ($ref->{'notpolled'}) {
		$state = 'notpolled';
	} elsif ($model =~ /^cisco AIR-/) {
		$state = 'present';
	} else {
		$state = 'missing';
		$sysname .= " $model";
	}
	my $clr = $palette{$state};
	
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

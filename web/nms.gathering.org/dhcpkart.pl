#! /usr/bin/perl
use CGI qw(fatalsToBrowser);
use GD;
use DBI;
use lib '../../include';
use nms;
my $cgi = CGI->new;

#my $greentimeout = 7200;
my $greentimeout = 15*60;
my $maxtimeout = $greentimeout*9;

my $dbh = nms::db_connect();

GD::Image->trueColor(1);
my $map = 'tg14-salkart.png';
die "$map does not exist" unless -e $map;
$img = GD::Image->new($map);

my $blk = $img->colorResolve(0, 0, 0);

$img->string(gdMediumBoldFont,0,0,"DHCP-lease status",$blk);
$img->string(gdSmallFont,0,20,"Last received DHCP-request",$blk);

# first  1/5: green (<30 min)
# middle 3/5: yellow -> red (30 min - 6 hours)
# last   1/5: blue (>6 hours)
my $grn = $img->colorResolve(0, 255, 0);
my $blu = $img->colorResolve(0, 0, 255);

my $l1 = 42 + (236 - 42)/5;
my $l2 = 236 - (236 - 42)/5;

$img->filledRectangle(32, 42, 53, $l1, $grn);
$img->string(gdSmallFont,56,$l1-8,($greentimeout/60)." min",$blk);

$img->filledRectangle(32, $l2, 53, 237, $blu);
$img->string(gdSmallFont,56,$l2-5,($maxtimeout/60)." min",$blk);

for my $y ($l1..$l2) {
	my $i = 1.0 - ($y - $l1) / ($l2 - $l1);
	my $clr = get_color($i);

	$img->filledRectangle(32,$y,53,$y+1,$clr);
}

my $q = $dbh->prepare('select switch,sysname,placement,EXTRACT(EPOCH FROM now() - last_ack) as age from switches natural join placements natural join dhcp order by sysname');
$q->execute();
while (my $ref = $q->fetchrow_hashref()) {
	my $age = $ref->{'age'};
	if (!defined($age) || $age > $maxtimeout) {
		$clr = $img->colorResolve(0, 0, 255);
	} elsif ($age < $greentimeout) {
		$clr = $img->colorResolve(0, 255, 0);
	} else {
		# 30 minutes = 0.0
		# 6 hours = 1.0
	
		my $intensity = log($age / $greentimeout) / log($maxtimeout/$greentimeout);
		$clr = get_color(1.0 - $intensity);
	}
	
	my $sysname = $ref->{'sysname'};
	if ($sysname !~ m/d0/i) { # don't draw distro-switches
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
	return $img->colorResolve(255.0, 255.0 * ($intensity ** $gamma), 0);
}

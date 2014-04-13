#! /usr/bin/perl
use CGI;
use GD;
use DBI;
use lib '../../include';
use nms;
my $cgi = CGI->new;

my $dbh = nms::db_connect();

GD::Image->trueColor(1);
$img = GD::Image->new('tg14-salkart.png');

my $blk = $img->colorResolve(0, 0, 0);

for my $y (42..236) {
	my $i = 3.0 * ($y - 236.0) / (42.0 - 237.0);
	my $clr = get_color($i);
	
	$img->filledRectangle(12,$y,33,$y+1,$clr);
}

$img->stringFT($blk, "/usr/share/fonts/truetype/msttcorefonts/Arial.ttf", 10, 0, 40, 47 + (236-42)*0.0/3.0, "1 Gbit/sec");
$img->stringFT($blk, "/usr/share/fonts/truetype/msttcorefonts/Arial.ttf", 10, 0, 40, 47 + (236-42)*1.0/3.0, "100 Mbit/sec");
$img->stringFT($blk, "/usr/share/fonts/truetype/msttcorefonts/Arial.ttf", 10, 0, 40, 47 + (236-42)*2.0/3.0, "10 Mbit/sec");
$img->stringFT($blk, "/usr/share/fonts/truetype/msttcorefonts/Arial.ttf", 10, 0, 40, 47 + (236-42)*3.0/3.0, "1 Mbit/sec");
$img->stringFT($blk, "/usr/share/fonts/truetype/msttcorefonts/Arial.ttf", 10, 0, 1000, 620, "NMS (C) 2005-2007 Tech:Server");

my $q = $dbh->prepare('select switch,port,bytes_in,bytes_out,placement,switchtype from switches natural join placements natural join get_datarate() where switchtype like \'%3100%\'');
$q->execute();
while (my $ref = $q->fetchrow_hashref()) {

	# for now:
	# 100kbit/port = all green
	# 1gbit/port = all red
	
	my $clr;

	if (defined($ref->{'bytes_in'})) {
		my $intensity = 0.0;
		my $traffic = 4.0 * ($ref->{'bytes_in'} + $ref->{'bytes_out'});  # average and convert to bits (should be about the same in practice)

		my $max = 100_000_000_000.0;   # 1Gbit
		my $min =       1_000_000.0;   # 1Mbit
		if ($traffic >= $min) {
			$intensity = log($traffic / $min) / log(10);
			$intensity = 4.0 if ($intensity > 4.0);
		}
		$clr = get_color($intensity);
	} else {
		$clr = $img->colorResolve(0, 0, 255);
	}
	
	$ref->{'placement'} =~ /\((\d+),(\d+)\),\((\d+),(\d+)\)/;
	my $npo = 48;
	my $f = ($ref->{'port'} - 1) % 2;
	my $po = ($ref->{'port'} - 1 - $f)/2;
	my $h = 2*($2-$4)/$npo;
	my $w = ($1-$3)/2;
	
	$img->filledRectangle($3+$w*$f,$4+$po*$h,$3+$w+$w*$f,$4+$h*($po+1),$clr);
#	$img->rectangle($3+$w*$f,$4+$po*$h,$3+$w+$w*$f,$4+$h*($po+1),$blk);
	$img->rectangle($3,$4,$1,$2,$blk);
}
$dbh->disconnect;

print $cgi->header(-type=>'image/png');
print $img->png;

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

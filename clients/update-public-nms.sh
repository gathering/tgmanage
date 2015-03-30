#!/bin/sh
YEAR=15
TGMANAGE=/root/tgmanage
DIR=/srv/www/nms-public.tg${YEAR}.gathering.org
set -x
mkdir -p $DIR

wget -qO$DIR/nettkart-dhcp.png.new http://nms.tg${YEAR}.gathering.org/dhcpkart.pl
wget -qO$DIR/led.txt.new http://nms.tg${YEAR}.gathering.org/led.pl
mv $DIR/nettkart-dhcp.png.new $DIR/nettkart-dhcp.png
mv $DIR/led.txt.new $DIR/led.txt
/usr/bin/perl $TGMANAGE/clients/update-public-speedometer.pl > $DIR/speedometer.json.tmp
mv $DIR/speedometer.json.tmp $DIR/speedometer.json

/usr/bin/perl -i -pe 'use POSIX qw(strftime); my $timestamp = strftime("%a, %d %b %Y %H:%M:%S %z", localtime(time())); s/Sist oppdatert:.*/Sist oppdatert: $timestamp/g;' $DIR/dhcp.html
/usr/bin/perl -i -pe 'use POSIX qw(strftime); my $timestamp = strftime("%a, %d %b %Y %H:%M:%S %z", localtime(time())); s/Sist oppdatert:.*/Sist oppdatert: $timestamp/g;' $DIR/trafikk.html

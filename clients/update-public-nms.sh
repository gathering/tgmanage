#!/bin/sh
DIR=/root/tgmanage/web/nms-public.gathering.org

wget -qO$DIR/nettkart-trafikk.png.new http://nms.tg14.gathering.org/nettkart.pl
wget -qO$DIR/nettkart-dhcp.png.new http://nms.tg14.gathering.org/dhcpkart.pl
wget -qO$DIR/led.txt.new http://nms.tg14.gathering.org/led.pl
mv $DIR/nettkart-trafikk.png.new $DIR/nettkart-trafikk.png
mv $DIR/nettkart-dhcp.png.new $DIR/nettkart-dhcp.png
mv $DIR/led.txt.new $DIR/led.txt

/usr/bin/perl -i -pe 'use POSIX qw(strftime); my $timestamp = strftime("%a, %d %b %Y %H:%M:%S %z", localtime(time())); s/Sist oppdatert:.*/Sist oppdatert: $timestamp/g;' $DIR/dhcp.html
/usr/bin/perl -i -pe 'use POSIX qw(strftime); my $timestamp = strftime("%a, %d %b %Y %H:%M:%S %z", localtime(time())); s/Sist oppdatert:.*/Sist oppdatert: $timestamp/g;' $DIR/trafikk.html

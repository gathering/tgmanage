#! /usr/bin/perl
use strict;
use warnings;
use CGI;
use File::Copy;

my $cgi = CGI->new;
my $img_filename = "/root/tgmanage/web/nms-public.gathering.org/weathermap.png";

# this must be done for windows
binmode STDOUT;
	
# flush headers
$|=1;
	
# print the image
print $cgi->header(-type=>'image/png; charset=utf-8', -refresh=>'10; weathermap.pl');
copy "$img_filename", \*STDOUT;

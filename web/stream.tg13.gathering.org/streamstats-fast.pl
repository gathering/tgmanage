#! /usr/bin/perl
use strict;
use warnings;
use POSIX;
use CGI qw(fatalsToBrowser);
	
my $port_spec = CGI::param('port');
my $proto_spec = CGI::param('proto');
my $audience_spec = CGI::param('audience');

print CGI::header(-type=>'image/png');

# I'm sure this is really safe
system("/srv/stream.tg13.gathering.org/fix_count.pl | /srv/stream.tg13.gathering.org/streamstats - $port_spec $proto_spec $audience_spec");
#system("/srv/stream.tg13.gathering.org/streamstats", "/home/techserver/cleaned_datacube.log", $port_spec, $proto_spec, $audience_spec);

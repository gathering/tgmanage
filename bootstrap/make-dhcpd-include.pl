#!/usr/bin/perl -I /root/tgmanage
use strict;
my $base = "/etc";
$base = $ARGV[0] if $#ARGV > -1;
$base .= "/" if not $base =~ m/\/$/ and not $base eq "";

my $dhcpd_base = $base . "dhcp/";
my $includeconfig = $dhcpd_base . "v4-generated-include.conf";

my $glob = $dhcpd_base . "conf-v4/*.conf";
my @configs = glob($glob);

open CONF, ">" . $includeconfig or die ( $! . " " . $includeconfig);
foreach my $config ( @configs )
{
	print CONF "include \"" . $config . "\";\n";
}
close CONF;

$includeconfig = $dhcpd_base . "v6-generated-include.conf";

my $glob = $dhcpd_base . "conf-v6/*.conf";
my @configs = glob($glob);

open CONF, ">" . $includeconfig or die ( $! . " " . $includeconfig);
foreach my $config ( @configs )
{
	print CONF "include \"" . $config . "\";\n";
}
close CONF;
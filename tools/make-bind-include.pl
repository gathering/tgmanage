#!/usr/bin/perl -I /root/tgmanage

# TODO: Port this to the "master|slave base" parameter syntax!

use strict;

unless ( (($#ARGV == 0 ) || ( $#ARGV == 1))
	&& (( $ARGV[0] eq "master" ) || ( $ARGV[0] eq "slave" )) )
{
	print STDERR "Invalid usage!\ncat netnames.txt | $0 <master|slave> [basedir]\n";
	exit 1;
}

my $role = $ARGV[0];

my $base = "/etc";
$base = $ARGV[1] if $#ARGV == 1;
$base .= "/" if not $base =~ m/\/$/ and not $base eq "";

my $bind_base = $base . "bind/";
my $masterinclude = $bind_base . "named.master-include.conf";
my $slaveinclude  = $bind_base . "named.slave-include.conf";

my $glob;
my @configs;

if ( $role eq "master" )
{
	$glob = $bind_base . "conf-master/*.conf";
	@configs = glob($glob);

	open CONF, ">" . $masterinclude or die ( $! . " " . $masterinclude);
	foreach my $config ( @configs )
	{
		print CONF "include \"" . $config . "\";\n";
	}
	close CONF;
}

if ( $role eq "slave" )
{
	$glob = $bind_base . "conf-slave/*.conf";
	@configs = glob($glob);

	open CONF, ">" . $slaveinclude or die ( $! . " " . $slaveinclude);
	foreach my $config ( @configs )
	{
		print CONF "include \"" . $config . "\";\n";
	}
	close CONF;
}

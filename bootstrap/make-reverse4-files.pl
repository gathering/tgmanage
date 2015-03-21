#!/usr/bin/perl -I /root/tgmanage
use strict;
use Net::IP;

BEGIN {
        require "include/config.pm";
        eval {
                require "include/config.local.pm";
        };
}

my $serial = strftime("%Y%m%d", localtime(time())) . "01";

unless ( (($#ARGV == 0 ) || ( $#ARGV == 1))
	&& (( $ARGV[0] eq "master" ) || ( $ARGV[0] eq "slave" )) )
{
	print STDERR "Invalid usage!\n$0 <master|slave> [basedir]\n";
	exit 1;
}

my $role = $ARGV[0];

my $base = "/etc";
$base = $ARGV[1] if $#ARGV == 1;
$base .= "/" if not $base =~ m/\/$/ and not $base eq "";

my $bind_base =  $base . "bind/";
my $dhcpd_base = $base . "dhcp/";
my $dhcp_revzones_file =  $dhcpd_base . "revzones.conf";
my $bind_pri_revzones_file = $bind_base . "named.reverse4.conf";
my $bind_sec_revzones_file = $bind_base . "named.slave-reverse4.conf";

my $pri_v4   = $nms::config::pri_v4;
my $pri_v6    = $nms::config::pri_v6;

my $sec_v4   = $nms::config::sec_v4;
my $sec_v6    = $nms::config::sec_v6;

my $base_ipv4 = Net::IP->new($nms::config::base_ipv4net) or die ("base_v4 fail");
my ($p_oct, $s_oct, $t_oct) = ($nms::config::base_ipv4net =~ m/^(\d+)\.(\d+)\.(\d+)\..*/);

$pri_v4 =~ m/^(\d+)\.(\d+)\.(\d+)\.(\d+).*/;
my ( $pp_oct, $ps_oct, $pt_oct, $pf_oct) = ( $1, $2, $3, $4 );
$sec_v4 =~ m/^(\d+)\.(\d+)\.(\d+)\.(\d+).*/;
my ( $sp_oct, $ss_oct, $st_oct, $sf_oct) = ( $1, $2, $3, $4 );

if ( $role eq "master" )
{
	open DFILE, ">" . $dhcp_revzones_file or die $!;
	open NFILE, ">" . $bind_pri_revzones_file or die $!;
}
elsif ( $role eq "slave" )
{
	open SFILE, ">" . $bind_sec_revzones_file or die $!;
}
else
{
	die ("WTF, role is neither 'master' or 'slave'");
}

while (1)
{

	my $block =  $p_oct . "." . $s_oct . "." . $t_oct . ".0/24";
	my $current = new Net::IP( $block ) or die ("new Net::IP failed for " . $block);

	my $rev_zone = $t_oct . "." .  $s_oct . "." . $p_oct . ".in-addr.arpa";

	if ( $role eq "master" )
	{
		# Generating IPv4-related reverse-stuff for
		# both bind9 and dhcp on master.

		print DFILE "zone " . $rev_zone . " { primary " . $nms::config::ddns_to . "; key DHCP_UPDATER; }\n";

		print NFILE "zone \"". $rev_zone ."\"	{\n";
		print NFILE "    type master;\n";
		print NFILE "    allow-update { key DHCP_UPDATER; };\n";
		print NFILE "    notify yes;\n";
		print NFILE "    allow-transfer { ns-xfr; ext-xfr; };\n";
		print NFILE "    file \"reverse/". $rev_zone .".zone\";\n";
		print NFILE "};\n\n";

		my $zfilename = $bind_base . "reverse/" . $rev_zone . ".zone";
		open ZFILE, ">", $zfilename;

		print ZFILE "; " . $zfilename . "\n";
		print ZFILE <<"EOF";
; Base reverse zones are updated from dhcpd -- DO NOT TOUCH!
\$TTL 3600
@	IN	SOA	$nms::config::pri_hostname.$nms::config::tgname.gathering.org.	abuse.gathering.org. (
                        $serial   ; serial
                        3600 ; refresh
                        1800 ; retry
                        608400 ; expire
                        3600 ) ; minimum and default TTL

		IN	NS	$nms::config::pri_hostname.$nms::config::tgname.gathering.org.
		IN	NS	$nms::config::sec_hostname.$nms::config::tgname.gathering.org.

\$ORIGIN $rev_zone.
EOF
		if ( ($pt_oct == $t_oct) && ($ps_oct == $s_oct) )
		{
			print ZFILE $pf_oct . "		IN	PTR	$nms::config::pri_hostname.$nms::config::tgname.gathering.org.\n";
		}
		if ( ($st_oct == $t_oct) && ($ss_oct == $s_oct) )
		{
			print ZFILE $sf_oct . "		IN	PTR	$nms::config::sec_hostname.$nms::config::tgname.gathering.org.\n";
		}
	}
	else
	{
		# AKA "if not master", as in "is slave".
		# A lot less work: update the named.slave-reverse4.conf file..
		print SFILE "zone \"". $rev_zone ."\"	{\n";
		print SFILE "    type slave;\n";
		print SFILE "    notify no;\n";
		print SFILE "    file \"slave/". $rev_zone .".cache\";\n";
		print SFILE "    masters { bootstrap; };\n";
		print SFILE "    allow-transfer { ns-xfr; ext-xfr; };\n";
		print SFILE "};\n\n";
	}

	if ( $current->last_int() == $base_ipv4->last_int() )
	{
		print STDERR "Reached last IP network. Finished\n";
		last;
	}
	$t_oct++;
}
# Close all files, even those that have never been opened ;)
close DFILE;
close NFILE;
close SFILE;

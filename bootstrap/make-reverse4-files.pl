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
my $dhcp_revzones_file =  $dhcpd_base . "v4-revzones.conf";
my $bind_pri_revzones_file = $bind_base . "named.reverse4.conf";
my $bind_sec_revzones_file = $bind_base . "named.slave-reverse4.conf";

my $base_ipv4 = Net::IP->new($nms::config::base_ipv4net) or die ("base_v4 fail");
my ($p_oct, $s_oct, $t_oct) = ($nms::config::base_ipv4net =~ m/^(\d+)\.(\d+)\.(\d+)\..*/);
my ($pp_oct, $ps_oct, $pt_oct, $pf_oct) = ($nms::config::pri_v4 =~ m/^(\d+)\.(\d+)\.(\d+)\.(\d+).*/);
my ($sp_oct, $ss_oct, $st_oct, $sf_oct) = ($nms::config::sec_v4 =~ m/^(\d+)\.(\d+)\.(\d+)\.(\d+).*/);

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

sub add_zone{
	my $block =  $p_oct . "." . $s_oct . "." . $t_oct . ".0/24";
	my $rev_zone = $t_oct . "." .  $s_oct . "." . $p_oct . ".in-addr.arpa";
		
	if ( $role eq "master" )
	{
		# Generating IPv4-related reverse-stuff for
		# both bind9 and dhcp on master.

		print DFILE <<"EOF";
zone "$rev_zone" {
	primary $nms::config::ddns_to;
	key DHCP_UPDATER;
}
EOF

		print NFILE <<"EOF";
// $block
zone "$rev_zone" {
	type master;
	allow-update { key DHCP_UPDATER; };
	notify yes;
	allow-transfer { ns-xfr; ext-xfr; };
	file "reverse/$rev_zone.zone";
};

EOF

		my $zfilename = $bind_base . "reverse/" . $rev_zone . ".zone";
		open ZFILE, ">", $zfilename;

		print ZFILE <<"EOF";
; $zfilename
; $block
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

		# add reverse if DNS-servers belong to zone
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
		# if not master, aka slave
		print SFILE <<"EOF";
// $block
zone "$rev_zone" {
	type slave;
	notify no;
	file "slave/$rev_zone.cache";
	masters { master_ns; };
	allow-transfer { ns-xfr; ext-xfr; };
};

EOF
	}
}

# for each /24 in the primary v4-net
while (1){
	my $current = Net::IP->new($block) or die ("Net::IP failed for " . $block);
	
	add_zone();
	
	if ( $current->last_int() == $base_ipv4->last_int() )
	{
		print STDERR "Reached last IP network. Finished.\n";
		last;
	}
	$t_oct++;
}

# for each specially defined /24
foreach my $special_net (@nms::config::extra_nets){
	# a.b.c.d/24
	$base_ipv4 = Net::IP->new($special_net) or die ("base_v4 fail");
	($p_oct, $s_oct, $t_oct) = ($special_net =~ m/^(\d+)\.(\d+)\.(\d+)\..*/);
	
	add_zone();
}

# Close all files, even those that have never been opened ;)
close DFILE;
close NFILE;
close SFILE;

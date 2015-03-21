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
	print STDERR "Invalid usage!\ncat netnames.txt | $0 <master|slave> [basedir]\n";
	exit 1;
}

my $role = $ARGV[0];

my $base = "/etc";
$base = $ARGV[1] if $#ARGV == 1;
$base .= "/" if not $base =~ m/\/$/ and not $base eq "";


print STDERR "Role is " . $role . "\n";
print STDERR "Base dir is " . $base . "\n";

my $bind_base =  $base . "bind/";
my $dhcpd_base = $base . "dhcp/";

my $bind_conf_master = $bind_base . "conf-master/";
my $bind_conf_slave  = $bind_base . "conf-slave/";

my $base_ipv4 = Net::IP->new( $nms::config::base_ipv4net );
my ($cp_oct, $cs_oct, $ct_oct) = ($nms::config::base_ipv4net =~ m/^(\d+)\.(\d+)\.(\d+)\..*/);

while ( <STDIN> ){
	next if ( $_ =~ m/^#/);
	my $line = $_;
	chomp $line;
	# <v4 net> <v6 net> <network-name>
	# 151.216.129.0/26 2a02:ed02:129a::/64 noc
	# we assume not smaller than /64 on v6
	die ("Invalid format on input") if not $line =~ m/^((\d+\.){3}\d+\/\d+)\s+(([a-fA-F0-9]+\:){1,4}\:\/\d+)\s+([\w|-]+).*/;
	my ( $v4_net, $v6_net, $name ) = ( $1, $3, $5 );
	
	my $master_config =  $bind_conf_master . $name . ".conf";
	my $slave_config =  $bind_conf_slave . $name . ".conf";
	my $zone_file = $bind_base . "dynamic/$name.$nms::config::tgname.gathering.org.zone";
		
	my $v4_range = Net::IP->new( $v4_net ) or die ("v4_net fail");
	my $v6_range = Net::IP->new( $v6_net ) or die ("v6_net fail");
	
	# DHCP4
	my $dhcp_dynconf_dir =  $dhcpd_base . "conf-v4/";
	my $dhconfig = $dhcp_dynconf_dir . $name . ".conf";

	if ( not -f $dhconfig )
	{
		print STDERR "Creating file " . $dhconfig . "\n";
		my $numhosts = $range->size();
		my $mask = $range->mask();
		my $router = $net_base . "." .  ($f_oct+1);
		my $first = $net_base . "." . ( $f_oct + 5 );

		my $last = $first;
		if ( $size < 24 )
		{
			# Net::IP iteration is crazyslow. So, we stopped using iterations.
			my $last_ip = $range->last_ip();
			$last_ip =~ m/(\d+)\.(\d+)\.(\d+)\.(\d+)/;
			$last = sprintf("%d.%d.%d.%d", $1, $2, $3, $4-2);
		}
		else { $last = $net_base . "." . ( $f_oct + $numhosts - 2 ); }

		#print STDERR "Name     : " . $name . "\n";
		#print STDERR "Net      : " . $net . "\n";
		#print STDERR "Mask     : " . $mask . "\n";
		#print STDERR "Router   : " . $router . "\n";
		#print STDERR "Size     : " . $size . "\n";
		#print STDERR "Numhosts : " . $numhosts . "\n";
		#print STDERR "First    : " . $first . "\n";
		#print STDERR "Last     : " . $last . "\n";

		open DFILE, ">" . $dhconfig or die ( $! . " " . $dhconfig);

		print DFILE "zone $name.$nms::config::tgname.gathering.org {\n";
		print DFILE "    primary $nms::config::ddns_to;\n";
		print DFILE "    key DHCP_UPDATER;\n";
		print DFILE "}\n\n";

		print DFILE "subnet $net netmask $mask {\n";
		print DFILE "    authoritative;\n";
		print DFILE "    option routers $router;\n";
		print DFILE "    option domain-name \"$name.$nms::config::tgname.gathering.org\";\n";
		print DFILE "    ddns-domainname \"$name.$nms::config::tgname.gathering.org\";\n";
		print DFILE "    range $first $last;\n";
		print DFILE "    ignore client-updates;\n";
		print DFILE "}\n\n";

		close DFILE;
	}
	
	# DHCP6
	my $dhcp_dynconf_dir =  $dhcpd_base . "conf-v6/";
	my $dhconfig = $dhcp_dynconf_dir . $name . ".conf";

	if ( not -f $dhconfig )
	{
		print STDERR "Creating file " . $dhconfig . "\n";
		my $numhosts = $range->size();
		my $mask = $range->mask();
		my $router = $net_base . "." .  ($f_oct+1);
		my $first = $net_base . "." . ( $f_oct + 5 );

		my $last = $first;
		if ( $size < 24 )
		{
			# Net::IP iteration is crazyslow. So, we stopped using iterations.
			my $last_ip = $range->last_ip();
			$last_ip =~ m/(\d+)\.(\d+)\.(\d+)\.(\d+)/;
			$last = sprintf("%d.%d.%d.%d", $1, $2, $3, $4-2);
		}
		else { $last = $net_base . "." . ( $f_oct + $numhosts - 2 ); }

		#print STDERR "Name     : " . $name . "\n";
		#print STDERR "Net      : " . $net . "\n";
		#print STDERR "Mask     : " . $mask . "\n";
		#print STDERR "Router   : " . $router . "\n";
		#print STDERR "Size     : " . $size . "\n";
		#print STDERR "Numhosts : " . $numhosts . "\n";
		#print STDERR "First    : " . $first . "\n";
		#print STDERR "Last     : " . $last . "\n";

		open DFILE, ">" . $dhconfig or die ( $! . " " . $dhconfig);

		print DFILE "zone $name.$nms::config::tgname.gathering.org {\n";
		print DFILE "    primary $nms::config::ddns_to;\n";
		print DFILE "    key DHCP_UPDATER;\n";
		print DFILE "}\n\n";

		print DFILE "subnet $net netmask $mask {\n";
		print DFILE "    authoritative;\n";
		print DFILE "    option routers $router;\n";
		print DFILE "    option domain-name \"$name.$nms::config::tgname.gathering.org\";\n";
		print DFILE "    ddns-domainname \"$name.$nms::config::tgname.gathering.org\";\n";
		print DFILE "    range $first $last;\n";
		print DFILE "    ignore client-updates;\n";
		print DFILE "}\n\n";

		close DFILE;
	}

	# Create zone files for bind9 on master/primary
	if ( ( not -f $zone_file ) && ( $role eq "master" ) )
	{
		print STDERR "Creating file " . $zone_file . "\n";
		open ZFILE, ">" . $zone_file or die ( $! . " " . $zone_file);
		print ZFILE << "EOF";
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
\$ORIGIN $name.$nms::config::tgname.gathering.org.
EOF
		close ZFILE;
	}
	
	# Create bind9 configuration files for zones.
	my $bind_file = "";
	$bind_file = $master_config if ( $role eq "master");
	$bind_file = $slave_config if ( $role eq "slave");
	die ("WTF, role does not match 'master' or 'slave'" ) if ( $bind_file eq "");

	if ( not -f $bind_file )
	{
		print STDERR "Creating file " . $bind_file . "\n";
		open NFILE, ">" . $bind_file or die ( $! . " " . $bind_file);

		print NFILE "zone \"$name.$nms::config::tgname.gathering.org\" {\n";
		if ( $role eq "master" ) {
			print NFILE "        type master;\n";
			print NFILE "        notify yes;\n";
			print NFILE "        allow-update { key DHCP_UPDATER; };\n";
			print NFILE "        file \"dynamic/$name.$nms::config::tgname.gathering.org.zone\";\n";
		}
		else
		{
			print NFILE "        type slave;\n";
			print NFILE "        notify no;\n";
			print NFILE "        masters { bootstrap; };\n";
			print NFILE "        file \"slave/$name.$nms::config::tgname.gathering.org.zone\";\n";
		}
		print NFILE "        allow-transfer { ns-xfr; };\n";
		print NFILE "};\n";

		close NFILE;
	}
}

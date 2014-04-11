#!/usr/bin/perl -I /root/tgmanage
use strict;

BEGIN {
        require "include/config.pm";
        eval {
                require "include/config.local.pm";
        };
}


use Net::IP;
use Net::IP qw(:PROC);

# FIXME: THIS IS NOT APPRORPIATE!
my $serial = `date +%Y%m%d01`;
chomp $serial;
# FIXME

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

my $dhcp_dynconf_dir =  $dhcpd_base . "conf.d/";
my $bind_conf_master = $bind_base . "conf-master/";
my $bind_conf_slave  = $bind_base . "conf-slave/";

my $tgname    = $nms::config::tgname;

my $pri_hostname     = $nms::config::pri_hostname;
my $pri_v4   = $nms::config::pri_v4;
my $pri_v6    = $nms::config::pri_v6;

my $sec_hostname     = $nms::config::sec_hostname;
my $sec_ptr   = $nms::config::sec_ptr;
my $sec_v6    = $nms::config::sec_v6;

my $ext_xfer  = $nms::config::ext_xfer;
my $ext_ns    = $nms::config::ext_ns;

my $ddns_key  = $nms::config::ddns_key;

my $base_ipv4net    = $nms::config::base_ipv4net;
my $base_ipv4prefix = $nms::config::base_ipv4prefix;

my $ddns_to = $nms::config::ddns_to;

my $base_ipv4 = new Net::IP( $base_ipv4net . "/" . $base_ipv4prefix );

$base_ipv4net =~ m/^(\d+)\.(\d+)\.(\d+)\..*/;
my ( $cp_oct, $cs_oct, $ct_oct ) = ( $1, $2, $3 );

while ( <STDIN> )
{
	next if ( $_ =~ m/^#/);
	my $line = $_;
	chomp $line;
	die ("Invalid format on input") if not $line =~ m/^(\d+)\.(\d+)\.(\d+)\.(\d+)\s+(\d+)\s+([\w|-]+)\s*.*/;
	my ( $p_oct, $s_oct, $t_oct, $f_oct, $size, $name ) = ( $1, $2, $3, $4, $5, $6 );
	

	my $dhconfig = $dhcp_dynconf_dir . $name . ".conf";
	my $master_config =  $bind_conf_master . $name . ".conf";
	my $slave_config =  $bind_conf_slave . $name . ".conf";
	my $zone_file = $bind_base . "dynamic/$name.$tgname.gathering.org.zone";
	
	my $net_base = $p_oct . "." .  $s_oct . "." .  $t_oct;
	my $net =  $net_base . "." .  $f_oct;
	my $range = new Net::IP( $net . "/" . $size ) or die ("oopxos");

	# Create configuration files for DHCP on master/primary
	if ( ( not -f $dhconfig ) && ( $role eq "master" ) )
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

		print DFILE "zone $name.$tgname.gathering.org {\n";
		print DFILE "    primary $ddns_to;\n";
		print DFILE "    key DHCP_UPDATER;\n";
		print DFILE "}\n\n";

		print DFILE "subnet $net netmask $mask {\n";
		print DFILE "    authoritative;\n";
		print DFILE "    option routers $router;\n";
		print DFILE "    option domain-name \"$name.$tgname.gathering.org\";\n";
		print DFILE "    ddns-domainname \"$name.$tgname.gathering.org\";\n";
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
@	IN	SOA	$pri_hostname.$tgname.gathering.org.	abuse.gathering.org. (
                        $serial   ; serial
                        3600 ; refresh
                        1800 ; retry
                        608400 ; expire
                        3600 ) ; minimum and default TTL

		IN	NS	$pri_hostname.$tgname.gathering.org.
		IN	NS	$sec_hostname.$tgname.gathering.org.
\$ORIGIN $name.$tgname.gathering.org.
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

		print NFILE "zone \"$name.$tgname.gathering.org\" {\n";
		if ( $role eq "master" ) {
			print NFILE "        type master;\n";
			print NFILE "        notify yes;\n";
			print NFILE "        allow-update { key DHCP_UPDATER; };\n";
			print NFILE "        file \"dynamic/$name.$tgname.gathering.org.zone\";\n";
		}
		else
		{
			print NFILE "        type slave;\n";
			print NFILE "        notify no;\n";
			print NFILE "        masters { bootstrap; };\n";
			print NFILE "        file \"slave/$name.$tgname.gathering.org.zone\";\n";
		}
		print NFILE "        allow-transfer { ns-xfr; };\n";
		print NFILE "};\n";

		close NFILE;
	}
}

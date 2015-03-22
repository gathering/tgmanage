#!/usr/bin/perl -I /root/tgmanage
use strict;
use Net::IP;
use NetAddr::IP;

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
	die ("Invalid format on input.\n") if not $line =~ m/^((\d+\.){3}\d+\/\d+)\s+(([a-fA-F0-9]+\:){1,4}\:\/\d+)\s+([\w|-]+).*/;
	my ( $v4_net, $v6_net, $name ) = ( $1, $3, $5 );
	
	my $master_config =  $bind_conf_master . $name . ".conf";
	my $slave_config =  $bind_conf_slave . $name . ".conf";
	my $zone_file = $bind_base . "dynamic/$name.$nms::config::tgname.gathering.org.zone";
	
	# DHCP4
	my $dhcp_dynconf_dir =  $dhcpd_base . "conf-v4/";
	my $dhconfig = $dhcp_dynconf_dir . $name . ".conf";

	if ( not -f $dhconfig ){
		print STDERR "Creating file " . $dhconfig . "\n";
		
		my $network = Net::IP->new($v4_net)->ip();
		my $netmask = Net::IP->new($v4_net)->mask();
		(my $first = NetAddr::IP->new($v4_net)->nth(3)) =~ s/\/[0-9]{1,2}//; # we reserve the three first addresses 
		(my $last = NetAddr::IP->new($v4_net)->last()) =~ s/\/[0-9]{1,2}//;
		(my $gw = NetAddr::IP->new($v4_net)->first()) =~ s/\/[0-9]{1,2}//;

		open DFILE, ">" . $dhconfig or die ( $! . " " . $dhconfig);

		print DFILE <<"EOF";
zone $name.$nms::config::tgname.gathering.org {
	primary $nms::config::ddns_to;
	key DHCP_UPDATER;
}
subnet $network netmask $netmask {
	option subnet-mask $netmask;
	option routers $gw;
	option domain-name "$name.$nms::config::tgname.gathering.org";
	ddns-domainname "$name.$nms::config::tgname.gathering.org";
	range $first $last;
}

EOF

		close DFILE;
	}
	
	# DHCP6
	my $dhcp_dynconf_dir =  $dhcpd_base . "conf-v6/";
	my $dhconfig = $dhcp_dynconf_dir . $name . ".conf";

	if ( not -f $dhconfig ){
		print STDERR "Creating file " . $dhconfig . "\n";
		
		my $network = Net::IP->new($v6_net)->short();
		my ($first, $last) = ("1000", "9999");
	
		print DFILE <<"EOF";
zone $name.$nms::config::tgname.gathering.org {
	primary $nms::config::ddns_to;
	key DHCP_UPDATER;
}
subnet6 $v6_net {
        option domain-name "$name.$nms::config::tgname.gathering.org";

	range6 ${network}${first} ${network}${last};
}

EOF

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

	if ( not -f $bind_file ){
		print STDERR "Creating file " . $bind_file . "\n";
		open NFILE, ">" . $bind_file or die ( $! . " " . $bind_file);

		print NFILE <<"EOF";
zone "$name.$nms::config::tgname.gathering.org" {
	allow-transfer { ns-xfr; };
EOF

		if ( $role eq "master" ) {
			print NFILE <<"EOF";
	type master;
	notify yes;
	allow-update { key DHCP_UPDATER; };
	file "dynamic/$name.$nms::config::tgname.gathering.org.zone";
};
EOF
		} else {
			print NFILE <<"EOF";
	type slave;
	notify no;
	masters { master_ns; };
	file "slave/$name.$nms::config::tgname.gathering.org.zone";
};
EOF
		}

		close NFILE;
	}
}

#!/usr/bin/perl
use strict;
use warnings;
package dlinkng::config;

# Common config
our $domain_name = ".net.party.bylan.net";	# DNS-name to append to hostnames (overriden later on for TG-mode)
our $dlink_def_user = "admin";			# Default user for a factory-default D-Link
our $dlink_def_ip = "10.90.90.90";		# IP for a factory-default D-Link
our $dlink_def_mask = "255.255.255.0";		# Mask for a factory-default D-Link
our $dlink_router_ip = "10.90.90.91";		# IP to use on the router/core
our $dlink_prefix = "30";			# Prefix to use when setting D-Link IP
our $dhcp4_proxyprofile = "DHCPv4Proxy";	# DHCPv4 proxy profile to use on IOS-XR
our $dhcp6_proxyprofile = "DHCPv6Proxy";	# DHCPv6 proxy profile to use on IOS-XR
our $vrf_prefix = "dlink";			# What to prefix the VRF-number (Thread ID) with
our $max_threads = 1;				# Max threads to use
our $dlink_host_suffix = "_DGS-3100";		# Suffix for hostname on the D-Link switches (needed by NMS)
our $default_coreswos = "ios";			# Default OS on coresw
our $dlink_lacp_start = '45';			# First port for LACP-group on D-Links
our $dlink_lacp_end = '48';			# Last port for LACP-group on D-Links
our $skip_last_port = 0;			# Skip last port -- set up as access port
our $use_ssh_cisco = 1;				# Use SSH towards Cisco-boxes
our $use_ssh_dlink = 0;				# Use SSH towards D-Link switches
our $access_vlan = '3602';			# VLAN to use for skipped port

# Specific config -- just declare empty
our $cisco_user = "";				# Username used when logging into the swithces
our $cisco_pass = "";				# Password used when logging into the switches
our $dhcprelay4_pri = "";			# Primary ip helper-address / ip dhcp relay address
our $dhcprelay4_sec = "";			# Secondary ip helper-address / ip dhcp relay address
our $dhcprelay6_pri = "";			# Primary ipv6 dhcp relay
our $dhcprelay6_sec = "";			# Secondary ipv6 dhcp relay
our $log_dir = "";				# Path to logfiles

# Placeholders, setting them after all config loaded
our ($po_config, $last_port_config, $os_regex, $os_info);

# Set variables that relies on all config being loaded
sub set_variables{
	# Custom Portchannel-config
	$po_config = {
		ios => [
			"logging event link-status",
			#"ip access-group end-user-protection in",
			#"ip directed-broadcast 2000",
			#"ipv6 nd prefix default 300 300 no-autoconfig",
			#"ipv6 nd managed-config-flag",
			#"ipv6 nd other-config-flag",
			#"ipv6 dhcp relay destination $dhcprelay6_pri",
			#"ipv6 dhcp relay destination $dhcprelay6_sec"
		],
		nx => [
			"",
		],
		xr => [
			"logging events link-status",
			"ipv4 directed-broadcast",
			"ipv6 nd prefix default 300 300 no-autoconfig",
			"ipv6 nd other-config-flag",
			"ipv6 nd managed-config-flag",
		],
	};

	# Custom last port config
	$last_port_config = {
		ios => [
			"logging event link-status",
			"switchport mode access",
			"switchport access vlan $access_vlan",
			"spanning-tree bpduguard enable",
		],
		nx => [
			"",
		],
		xr => [
			"",
		],
	};

	# Define what OS-version a coresw runs
	# NX, XR, XE, etc
	# The regex is matched against $coreswip
	$os_regex = {
		ios => 'iosbox',
		nx => 'flexusnexus',
		xr => 'c01',
	};

	# Configure settings for each OS
	$os_info = {
		ios => {
			max_sessions => 10,
		},
		nx => {
			# define 64 sessions on nxos
			# nx-os# conf t
			# nx-os(config)# feature dhcp
			# nx-os(config)# line vty
			# nx-os(config-line)# session-limit 64
			max_sessions => 50,
		},
		xr => {
			# telnet vrf default ipv4 server max-servers 100 access-list MGNTv4
			# telnet vrf default ipv6 server max-servers 100 access-list MGNTv6
			max_sessions => 50,
		},
	};
}

# Load ByLAN related configuration
sub load_bylan_config{
	# Define bylan-dir, and add it to %INC
	my $bylan_dir;
	BEGIN {
		use FindBin;
		$bylan_dir = "$FindBin::Bin"; # Assume working-folder is the path where this script resides
	}
	use lib $bylan_dir;
	use bylan;
	use Getopt::Long;
	
	# Load config
	my $config_file = "$bylan_dir/bylan.conf";
	my $conf = Config::General->new(
		-ConfigFile => $config_file,
		-InterPolateVars => 1);
	my %config = $conf->getall;
	
	# Options
	$cisco_user = "$config{switches}->{user}";		# Username used when logging into the swithces
	$cisco_pass = "$config{switches}->{pw}";		# Password used when logging into the switches
	$dhcprelay4_pri = "$config{servers}->{dhcp1_ipv4}";	# Primary ip helper-address / ip dhcp relay address
	$dhcprelay4_sec = "$config{servers}->{dhcp2_ipv4}";	# Secondary ip helper-address / ip dhcp relay address
	$dhcprelay6_pri = "$config{servers}->{dhcp1_ipv6}";	# Primary ipv6 dhcp relay
	$dhcprelay6_sec = "$config{servers}->{dhcp2_ipv6}";	# Secondary ipv6 dhcp relay
	$log_dir = "$bylan_dir/logs/telnet";			# Path to logfiles
}

# Load TG related configuration
sub load_tg_config{
	my $tg_dir = '/root/tgmanage';
	BEGIN {
	        require "$tg_dir/include/config.pm";
	        eval {
	                require "$tg_dir/include/config.local.pm";
	        };
	}

	# Options
	$cisco_user = "$nms::config::ios_user";		# Username used when logging into the swithces
	$cisco_pass = "$nms::config::ios_pass";		# Password used when logging into the switches
	$domain_name = ".infra.$nms::config::tgname.gathering.org";	# DNS-name to append to hostnames
	$dhcprelay4_pri = "$nms::config::dhcp_server1";	# Primary ip helper-address / ip dhcp relay address
	$dhcprelay4_sec = "$nms::config::dhcp_server2";	# Secondary ip helper-address / ip dhcp relay address
	$log_dir = "$tg_dir/dlink-ng/log";		# Path to logfiles	
}

# Uncomment the one you want
#load_bylan_config();
#load_tg_config();

# Set last variables that depend on the config above being set
set_variables();


1;

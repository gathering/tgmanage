#!/usr/bin/perl -I /root/tgmanage/
use warnings;
use strict;
use lib '..';
BEGIN {
        require "include/config.pm";
        eval {
                require "include/config.local.pm";
        };
}
use Net::Telnet::Cisco;
use Net::Ping;
use Net::IP;
use Term::ANSIColor;
use threads;
use threads::shared;
use Thread::Queue;
use Getopt::Long;

# Options
my $cisco_user = "$nms::config::ios_user";		# Username used when logging into the swithces
my $cisco_pass = "$nms::config::ios_pass";		# Password used when logging into the switches
my $domain_name = ".infra.$nms::config::tgname.gathering.org";	# DNS-name to append to hostnames
my $dlink_def_user = "admin";				# Default user for a factory-default D-Link
my $dlink_def_ip = "10.90.90.90";			# IP for a factory-default D-Link
my $dlink_def_mask = "255.255.255.0";			# Mask for a factory-default D-Link
my $dlink_router_ip = "10.90.90.91";			# IP to use on the router/core
my $dlink_prefix = "30";				# Prefix to use when setting D-Link IP
my $dhcprelay4_pri = "$nms::config::dhcp_server1";	# Primary ip helper-address / ip dhcp relay address
my $dhcprelay4_sec = "$nms::config::dhcp_server2";	# Secondary ip helper-address / ip dhcp relay address
my $dhcprelay6_pri = "";				# Primary ipv6 dhcp relay
my $dhcprelay6_sec = "";				# Secondary ipv6 dhcp relay
my $vrf_prefix = "dlink";				# What to prefix the VRF-number (Thread ID) with
my $max_threads = 20;					# Max threads to use
my $dlink_host_suffix = "_DGS-3100";			# Suffix for hostname on the D-Link switches (needed by NMS)
my $log_dir = "dlink-ng/log";				# Path to logfiles
my $default_coreswos = "ios";				# Default OS on coresw
my $dlink_lacp_start = '45';				# First port for LACP-group on D-Links
my $dlink_lacp_end = '48';				# Last port for LACP-group on D-Links
my $skip_last_port = 1;					# Skip last port -- set up as access port
my $access_vlan = '3602';				# VLAN to use for skipped port

# Stuff
my $switchq = Thread::Queue->new(); 	# Queue to put switches in
my $switches : shared = 0;		# Number of successful switches
my $failed_switches : shared = 0;	# Number of failed switches
my $total_time : shared = 0;		# Total time spent for all switches
my %telnet_sessions : shared;		# Number of sessions currently in use
my $DLINK_TEMPLATE;			# Filehandle used for reading D-Link template

# Custom Portchannel-config
my $po_config = {
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
};

# Custom last port config
my $last_port_config = {
	ios => [
		"logging event link-status",
		"switchport mode access",
		"switchport access vlan $access_vlan",
		"spanning-tree bpduguard enable",
	],
	nx => [
		"",
	],
};

# Define what OS-version a coresw runs
# NX, XR, XE, etc
# The regex is matched against $coreswip
my $os_regex = {
	nx => 'flexusnexus',
};

# Configure settings for each OS
my $os_info = {
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
};

# Autoflush
$| = 1;

# Get options
my ($cisco_config, $single_switch, $dlink_config, $save_config, $skipped_port_only, $skipped_port_desc_only, $no_skip);
if (@ARGV > 0) {
	GetOptions(
	'c|cisco|ciscoconfig'	=> \$cisco_config,		# Configure on the Cisco-side only (Portchannel, interfaces, etc)
	's|switch=s'		=> \$single_switch,		# Configure a single switch
	'd|dlink|dlinkconfig=s'	=> \$dlink_config,		# Push D-Link-template-config to D-Link (not used @ TG)
	'w|write'		=> \$save_config,		# Write config on Cisco-side
	'portskip'		=> \$skipped_port_only,		# Configure the skipped port only (Cisco-side)
	'skipdesc'		=> \$skipped_port_desc_only,	# Configure the skipped port description only (Cisco-side)
	'noskip'		=> \$no_skip			# Override $skip_last_port
	)
}

# Exit if D-Link template file doesn't exist
if ($dlink_config){
	unless(-e $dlink_config){
		die("File '$dlink_config' does not exists. Aborting.\n");
	}
}

# Exit if $cisco_config and $skipped_port_only or $skipped_port_desc_only is set
if ($cisco_config && ($skipped_port_only || $skipped_port_desc_only)){
	die("\$cisco_config and \$skipped_port_only (or \$skipped_port_desc_only) can't be used together.\n");
}

# Update $skip_last_port if $no_skip is set
if ($no_skip){
	$skip_last_port = 0;
}

# If skipdesc, assume $skipped_port_only
if ($skipped_port_desc_only){
	$skipped_port_only = 1;
}

# Print stuff
sub log_it{
	my ($logtype, $color, $switchname, $msg) = @_;
	printf ("%-38s %s\n", colored("$logtype", "$color") . "/" . colored("$switchname", "bold") . ":", "$msg");
}

# INFO-logs
sub info{
	my ($switchname, $msg) = @_;
	log_it("INFO", "blue", $switchname, $msg);
	return 1;
}

# ERROR-logs
sub error{
	my ($switchname, $msg) = @_;
	printf ("%-38s %s\n", colored("ERROR", "red") . "/" . colored("$switchname", "bold") . ":", "$msg");
	return 0;
}

# Debug from Net::Telnet::Cisco
sub debug{
	my ($switchname, $errmsg) = @_;
	
	if ($errmsg){
		foreach my $line (split('\\n', $errmsg)){
			error($switchname, $line);
		}
	}
}

# Abort
sub abort{
	my ($switchname, $t1, $t2) = @_;
	
	$t1->close if defined($t1);
	$t2->close if defined($t2);
	
	return error($switchname, "Aborting.");	
}

# Set coreswos
sub set_coreswos{
	my $coreswip = shift;
	
	my $os = $default_coreswos;
	
	foreach my $swos ( sort keys %$os_regex ){
		$os = $swos if ($coreswip =~ m/$os_regex->{$swos}/);
	}
	
	return $os;
}

# Is NX-OS?
sub is_nx{
	my $coreswos = shift;
	return 1 if ($coreswos =~ m/^nx$/i);
	return 0;
}

# Cisco-ping
sub cisco_ping{
	my ($cisco, $ip, $timeout, $coreswos, $vrf) = @_;
	my $cmd;
	
	if (is_nx($coreswos)){
		$cmd = "ping $ip count 1 timeout 1";
		$cmd .= " vrf ${vrf_prefix}${vrf}" if ($vrf && defined($vrf));
	} else {
		# IOS
		$cmd = "ping";
		$cmd .= " vrf ${vrf_prefix}${vrf}" if ($vrf && defined($vrf));
		$cmd .= " $ip repeat 1 timeout 1";
	}
	
	my $pong = 0;
	my $tries = 0;
	while (($pong == 0) && ($tries < $timeout)){
		my @res = $cisco->cmd($cmd);
		
		# if blank, try again
		# happens at least on ME3600X
		next unless @res;

		# sleep if it complains about no valid source address
		#  % VRF does not have a usable source address
		# this is caused by no link, or network not propagated
		# observed on WS-C6506-E with sup720 running 122-33.SXJ5
		sleep 1 if ("@res" =~ m/VRF does not have a usable source address/);
		
		if (is_nx($coreswos)){
			$pong = 1 if ($res[1] =~ m/^64 bytes from $ip/i);
		} else {
			$pong = 1 if ($res[-1] =~ m/^\s*Success rate is 100 percent/i);
		}
		$tries++;
	}
	return $pong;
}

# Net::Ping-ping
sub pong{
	my ($ip, $timeout) = @_;
	my $pong = 0;
	my $tries = 0;
	
	while(($pong == 0) && ($tries < $timeout)){
		my $p = Net::Ping->new();
		
		if ($p->ping($ip, 5)) {
			$pong = 1;
		}
		
		$tries++;
	}
	return $pong;
}

# Create login to D-Link
sub dlink_login{
	my ($switch, $ip, $vrf, $telnet_source) = @_;

	my $dlink = Net::Telnet::Cisco->new(
			Host => $switch->{coreswip} . $domain_name,
			Errmode => 'return',
			output_log => "$log_dir/output-$switch->{coreswip}.log",
			input_log => "$log_dir/input-$switch->{coreswip}.log",
			Prompt => '/\S+[#>]/',
			Timeout => 60
			);
	
	unless (defined($dlink)) {
		return error($switch->{switchname}, "Could not connect to '$switch->{coreswip}'.");
	}

	info($switch->{switchname}, "Logging in to coreswitch '$switch->{coreswip}' to telnet to D-Link.");
	
	unless ($dlink->login($cisco_user, $cisco_pass)){
		$dlink->close;
		return error($switch->{switchname}, "Can't log in to coreswitch '$switch->{coreswip}' (to telnet to D-Link).");
	}
			
	$dlink->enable;
	debug($switch->{switchname}, $dlink->errmsg);

	my $cmd;
	if (is_nx($switch->{coreswos})){
		$cmd = "telnet $ip";
		$cmd .= " vrf ${vrf_prefix}${vrf}" if ($vrf && defined($vrf));
		$cmd .= " source $telnet_source" if ($telnet_source && defined($telnet_source));
	} else {
		# IOS
		$cmd = "telnet $ip";
		$cmd .= " /vrf ${vrf_prefix}${vrf}" if ($vrf && defined($vrf));
		$cmd .= " /source-interface $telnet_source" if ($telnet_source && defined($telnet_source));
	}
	
	info($switch->{switchname}, "Telneting to D-Link.");
	$dlink->print($cmd);

	info($switch->{switchname}, "Waiting for login prompt.");
	$dlink->waitfor('/User ?Name:/')
		or return abort($switch->{switchname}, $dlink);
	
	info($switch->{switchname}, "Got login prompt, logging in.");
	telnet_print($switch, $dlink, '', $dlink_def_user, 0)
		or return abort($switch->{switchname}, $dlink);
		
	info($switch->{switchname}, "Waiting for prompt.");
	$dlink->waitfor('/\S+\#/')
		or return abort($switch->{switchname}, $dlink);
	
	# disable CLI paging
	telnet_print($switch, $dlink, '', "disable clipaging")
		or return abort($switch->{switchname}, $dlink);

	info($switch->{switchname}, "Logged in to D-Link");
	return $dlink;
}

# Execute telnet-command
sub telnet_cmd{
	my ($switch, $telnet, $cmd) = @_;
			
	unless ($telnet->cmd($cmd)){
		error($switch->{switchname}, "Command '$cmd' failed");
		debug($switch->{switchname}, $telnet->errmsg);
		return 0;
	}
	
	return 1;
}

# Execute telnet-print
sub telnet_print{
	my ($switch, $telnet, $telnet2, $cmd, $waitfor) = @_;
		
	unless (defined($waitfor)){
			$waitfor = 1;
	}
	
	unless ($telnet->print($cmd)){
		error($switch->{switchname}, "Command '$cmd' failed.");
		debug($switch->{switchname}, $telnet->errmsg);
		return 0;
	}
	
	if ($waitfor){
		$telnet->waitfor('/\S+\#/') or return 0;
	}
			
	return 1;
}

# Make sure interface actually is shut
sub no_no_shut{
	my ($switch, $cisco, $port) = @_;
	
	info($switch->{switchname}, "Making sure interface $port /REALLY/ gets shut.");
	
	# There is a few reasons as to why we want to do this.
	# On some boxes/OSes, default config for an interface is 'no shut'.
	# On some boxes/OSes, the 'shut' command isn't applied right away after
	# you do a 'shut'.
	
	my $tries = 0;
	my $return = 0;
	
	while (1){
		if($tries >= 5){
			# max 5 tries
			last;
		}
		
		sleep 1; # wait a bit
		
		telnet_cmd($switch, $cisco, "shut")
			or return abort($switch->{switchname}, $cisco); 

		# now we need to check that the 'running config' actually reflects this

		my @shut_info = $cisco->cmd("do sh run int $port | i shutdown");
		
		unless(@shut_info){
			$tries++;
			next;
		}
		
		my $shut = "@shut_info";
		chomp($shut);
		
		if ($shut =~ m/shutdown/i){
			$return = 1;
			last;
		} else {
			$tries++;
			next;
		}
	}
	
	return $return;
}

# Reset all interfaces
sub reset_interfaces{
	my ($switch, $cisco) = @_;
	
	# Take down interface
	info($switch->{switchname}, "Resetting interfaces.");
	
	telnet_cmd($switch, $cisco, "conf t")
		or return abort($switch->{switchname}, $cisco);
	
	# Remove old config/return to defaults on interfaces
	# We also shut them to avoid D-Link looping
	foreach my $port (@{$switch->{ports}}){
		telnet_cmd($switch, $cisco, "default int $port")
			or return abort($switch->{switchname}, $cisco);
		telnet_cmd($switch, $cisco, "int $port")
			or return abort($switch->{switchname}, $cisco);
		no_no_shut($switch, $cisco, $port)
			or return abort($switch->{switchname}, $cisco);
		telnet_cmd($switch, $cisco, "no switchport")
			or return abort($switch->{switchname}, $cisco);
	}

	# Remove portchannel
	if(is_nx($switch->{coreswos})){
		# NX-OS
		telnet_cmd($switch, $cisco, "no int Po$switch->{etherchannel}")
			or return abort($switch->{switchname}, $cisco);
	} else {
		# IOS fails on the next command, if the portchannel doesn't exist
		# Ignore error on this command
		$cisco->cmd("no int Po$switch->{etherchannel}");
	}

	telnet_cmd($switch, $cisco, "end")
		or return abort($switch->{switchname}, $cisco);
		
	return 1;
}

# Push D-Link template config to a D-Link
sub push_dlink_template_config{
	my $switch = shift;	# switchinfo
	
	# No need to bounce via Cisco-box; login directly to D-Link
	my $dlink = Net::Telnet::Cisco->new(
			Host => $switch->{ipv4address},
			Errmode => 'return',
			output_log => "$log_dir/output-$switch->{ipv4address}.log",
			input_log => "$log_dir/input-$switch->{ipv4address}.log",
			Prompt => '/\S+[#>]/',
			Timeout => 60
			);
	
	unless (defined($dlink)) {
		return error($switch->{switchname}, "Could not connect to '$switch->{switchname}' ($switch->{ipv4}).");
	}

	info($switch->{switchname}, "Logging in to D-Link '$switch->{switchname}' ($switch->{ipv4address}).");
	$dlink->waitfor('/User ?Name:/')
		or return abort($switch->{switchname}, $dlink);
	
	info($switch->{switchname}, "Got login prompt, logging in.");
	telnet_print($switch, $dlink, '', $dlink_def_user, 0)
		or return abort($switch->{switchname}, $dlink);
	
	info($switch->{switchname}, "Waiting for prompt.");
	$dlink->waitfor('/\S+\#/')
		or return abort($switch->{switchname}, $dlink);
	
	# disable CLI paging
	telnet_print($switch, $dlink, '', "disable clipaging")
		or return abort($switch->{switchname}, $dlink);
	
	info($switch->{switchname}, "Logged in to D-Link");
	
	# Done logging in, let's configure stuff
	info($switch->{switchname}, "Opening D-Link template file ($dlink_config).");
	open $DLINK_TEMPLATE, '<', $dlink_config or return error($switch->{switchname}, "Couldn't open D-Link template ($dlink_config): $!");

	info($switch->{switchname}, "Applying config from D-Link template file ($dlink_config).");
	
	while (my $line=<$DLINK_TEMPLATE>) {
		chomp $line;
		
		next if ($line =~ m/^\s*(((#|\!).*)|$)/);	# skip if comment, or blank line

		telnet_print($switch, $dlink, '', $line)
			or return abort($switch->{switchname}, $dlink);
			
		sleep 1; # The D-Link's are a bit slow...
	}

	close $DLINK_TEMPLATE or return error($switch->{switchname}, "Couldn't close D-Link template ($dlink_config): $!");

	info($switch->{switchname}, "Done applying config from D-Link template file ($dlink_config). Saving...");

	# Save config + logout
	telnet_print($switch, $dlink, '', "save", 0)
		or return abort($switch->{switchname}, $dlink);
	telnet_print($switch, $dlink, '', "Y")
		or return abort($switch->{switchname}, $dlink);
	telnet_print($switch, $dlink, '', "logout")
		or return abort($switch->{switchname}, $dlink);

	# Done
	log_it("SUCCESS", "green", $switch->{switchname}, "Done pushing D-Link template config to switch $switch->{switchname} ($switch->{ipv4address}). \\o/");
	$dlink->close;
	return 1;
}

# Setup a switch
sub setup{
	my $switch = shift;		# switchinfo
	my $vrf = threads->tid();	# use thread ID as VRF-number
	
	# Remove last port if we're skipping it
	my $skipped_port;
	if ($skip_last_port){
		$skipped_port = pop(@{$switch->{ports}});
	}
	
	if($skipped_port_only){
		info($switch->{switchname}, "Configuring skipped port only.");
	}
	
	if($cisco_config){
		info($switch->{switchname}, "Configuring things on the Cisco-side only.");
	}
	
	unless($cisco_config || $skipped_port_only){
		info($switch->{switchname}, "Starting configuration of $switch->{switchname} ($switch->{ipv4address}).");
		info($switch->{switchname}, "Trying to ping $switch->{ipv4address}.");
	
		if (pong($switch->{ipv4address}, 1)){
			# push template-config to D-Link if template-file is given as argument
			if($dlink_config){
				log_it("INFO", "green", $switch->{switchname}, "Switch $switch->{switchname} ($switch->{ipv4address}) is already responding to ping! \\o/");
				info($switch->{switchname}, "Going to push D-Link template config to switch $switch->{switchname} ($switch->{ipv4address})");
				return push_dlink_template_config($switch);
			} else {
				# if not
				log_it("INFO", "green", $switch->{switchname}, "Skipping $switch->{switchname} ($switch->{ipv4address}): is already responding to ping! \\o/");
				return 1;
			}
		}
	
		info($switch->{switchname}, "Not responding to ping, configuring device.");
	}

	info($switch->{switchname}, "Connecting to coreswitch '$switch->{coreswip}'.");

	my $cisco = Net::Telnet::Cisco->new(
			Host => $switch->{coreswip} . $domain_name,
			Errmode => 'return',
			output_log => "$log_dir/output-$switch->{coreswip}.log",
			input_log => "$log_dir/input-$switch->{coreswip}.log",
			Prompt => '/\S+[#>]/',
			Timeout => 60
			);

 	unless (defined($cisco)){
		return error($switch->{switchname}, "Could not connect to '$switch->{coreswip}'.");
	}

	info($switch->{switchname}, "Logging in to coreswitch '$switch->{coreswip}'.");
	
	unless ($cisco->login($cisco_user, $cisco_pass)){
		$cisco->close;
		return error($switch->{switchname}, "Can't log in to '$switch->{coreswip}'.");
	}
	
	$cisco->enable;
	debug($switch->{switchname}, $cisco->errmsg);

	# Disable paging
	telnet_cmd($switch, $cisco, "terminal length 0")
		or return abort($switch->{switchname}, $cisco);
	
	unless($cisco_config || $skipped_port_only){
		# Prepare ports
		reset_interfaces($switch, $cisco)
			or return abort($switch->{switchname}, $cisco);

		# Set up port 1 for D-Link telneting	
		telnet_cmd($switch, $cisco, "conf t")
			or return abort($switch->{switchname}, $cisco);

		info($switch->{switchname}, "Enabling VRF (${vrf_prefix}${vrf}). Applying to interface.");
		if(is_nx($switch->{coreswos})){
			# Remove previous VRF
			# No error-check on the next command, as NX-OS
			# spits out "% VRF dlink-X not found"
			# making Net::Telnet::Cisco think it's an error
			
			# Extra overhead to delete, not used
			#$cisco->cmd("no vrf context ${vrf_prefix}${vrf}");
			#sleep 10;	# NX-OS seems to need some time to delete a VRF
		
			# Create VRF
			telnet_cmd($switch, $cisco, "vrf context ${vrf_prefix}${vrf}")
				or return abort($switch->{switchname}, $cisco);
		} else {
			# IOS
			# IOS fails on the next command, if the vrf doesn't exist
			# Ignore error on this command
			
			# Extra overhead to delete, not used
			#$cisco->cmd("no ip vrf ${vrf_prefix}${vrf}");
			
			# Create VRF
			telnet_cmd($switch, $cisco, "ip vrf ${vrf_prefix}${vrf}")
				or return abort($switch->{switchname}, $cisco);
			telnet_cmd($switch, $cisco, "rd $vrf:$vrf")
				or return abort($switch->{switchname}, $cisco);
		}
	
		# Configure port #1
		telnet_cmd($switch, $cisco, "int " . @{$switch->{ports}}[0])
			or return abort($switch->{switchname}, $cisco);
		telnet_cmd($switch, $cisco, "no switchport")
			or return abort($switch->{switchname}, $cisco);
		
		if(is_nx($switch->{coreswos})){
			# No error-check on the next command, as NX-OS
			# spits out "% Deleted all L3 config on interface Ethernet1/45"
			# making Net::Telnet::Cisco think it's an error
		
			$cisco->cmd("vrf member ${vrf_prefix}${vrf}");
		} else {
			# IOS
			telnet_cmd($switch, $cisco, "ip vrf forwarding ${vrf_prefix}${vrf}")
				or return abort($switch->{switchname}, $cisco);
		}
	
		# Add temporary D-Link IP
		info($switch->{switchname}, "Adding IP-address to interface.");

		telnet_cmd($switch, $cisco, "ip address $dlink_router_ip $dlink_def_mask")
			or return abort($switch->{switchname}, $cisco);
	
		# 'no shut'-patrol reporting in!
		telnet_cmd($switch, $cisco, "no shut")
			or return abort($switch->{switchname}, $cisco); 
	
		telnet_cmd($switch, $cisco, "end")
			or return abort($switch->{switchname}, $cisco);

		info($switch->{switchname}, "Waiting for D-Link to answer on $dlink_def_ip in VRF ${vrf_prefix}${vrf} on port #1 (" . @{$switch->{ports}}[0] . ").");
	
		# Use port 1 if ping succeeds
		my $p_count = 0;
		my $dlink_port = @{$switch->{ports}}[$p_count];
		
		until (cisco_ping($cisco, $dlink_def_ip, 30, $switch->{coreswos}, $vrf)) {
			# Did not ping, let's try next port
			# We do this because port#1 might be damaged/not patched
			
			# First we need to check if there are more ports to test
			if ($p_count >= $#{$switch->{ports}}){
				# Current port is last port available
				# Since it did not ping, we reset all interfaces
				
				reset_interfaces($switch, $cisco)
					or return abort($switch->{switchname}, $cisco);
				$cisco->close;
				return error($switch->{switchname}, "No more ports on $switch->{switchname}. Aborting.");
			}
			
			# Use next port
			$p_count++;
			
			info($switch->{switchname}, "D-Link on port #" . ($p_count) . " ($dlink_port) did not respond. Trying next port (" . @{$switch->{ports}}[$p_count] . ").");
			
			# Try next port, reset old port
			telnet_cmd($switch, $cisco, "conf t")
				or return abort($switch->{switchname}, $cisco);
			telnet_cmd($switch, $cisco, "default int $dlink_port")
				or return abort($switch->{switchname}, $cisco);
			telnet_cmd($switch, $cisco, "int $dlink_port")
				or return abort($switch->{switchname}, $cisco);
			no_no_shut($switch, $cisco, $dlink_port)
				or return abort($switch->{switchname}, $cisco);
				
			# Set new port
			$dlink_port = @{$switch->{ports}}[$p_count];
			
			# Configure new port
			telnet_cmd($switch, $cisco, "int $dlink_port")
				or return abort($switch->{switchname}, $cisco);
			telnet_cmd($switch, $cisco, "no switchport")
				or return abort($switch->{switchname}, $cisco);
		
			if(is_nx($switch->{coreswos})){
				# No error-check on the next command, as NX-OS
				# spits out "% Deleted all L3 config on interface Ethernet1/45"
				# making Net::Telnet::Cisco think it's an error

				$cisco->cmd("vrf member ${vrf_prefix}${vrf}");
			} else {
				# IOS
				telnet_cmd($switch, $cisco, "ip vrf forwarding ${vrf_prefix}${vrf}")
					or return abort($switch->{switchname}, $cisco);
			}
			
			telnet_cmd($switch, $cisco, "ip address $dlink_router_ip $dlink_def_mask")
				or return abort($switch->{switchname}, $cisco);
			# 'no shut'-patrol reporting in!
			telnet_cmd($switch, $cisco, "no shut")
			 	or return abort($switch->{switchname}, $cisco);
			telnet_cmd($switch, $cisco, "end")
				or return abort($switch->{switchname}, $cisco);
		
			info($switch->{switchname}, "Waiting for D-Link to answer on $dlink_def_ip in VRF ${vrf_prefix}${vrf} on port #" . ($p_count+1) . " (" . @{$switch->{ports}}[$p_count] . ").");
		}

		# Telnet to D-Link
		info($switch->{switchname}, "Starting D-Link config phase 1.");
		my $dlink = dlink_login($switch, $dlink_def_ip, $vrf)
			or return abort($switch->{switchname}, $cisco);

		info($switch->{switchname}, "Setting hostname to $switch->{switchname}${dlink_host_suffix}");
		telnet_print($switch, $dlink, $cisco, "config snmp system_name $switch->{switchname}${dlink_host_suffix}")
			or return abort($switch->{switchname}, $cisco, $dlink);
		
		info($switch->{switchname}, "Adding LACP. Enabling STP.");
		telnet_print($switch, $dlink, $cisco, "create link_aggregation group_id 1 type lacp")
			or return abort($switch->{switchname}, $cisco, $dlink);
		telnet_print($switch, $dlink, $cisco, "config link_aggregation group_id 1 ports 1:($dlink_lacp_start-$dlink_lacp_end)")
			or return abort($switch->{switchname}, $cisco, $dlink);
		telnet_print($switch, $dlink, $cisco, "enable stp")
			or return abort($switch->{switchname}, $cisco, $dlink);
	
		info($switch->{switchname}, "STP enabled, logging in again.");
		$dlink->close;

		unless (cisco_ping($cisco, $dlink_def_ip, 60, $switch->{coreswos}, $vrf)) {
			reset_interfaces($switch, $cisco)
				or return abort($switch->{switchname}, $cisco);
			$cisco->close;
			return error($switch->{switchname}, "Can't login to $switch->{switchname} on $dlink_def_ip, aborting.");
		}

		$dlink = dlink_login($switch, $dlink_def_ip, $vrf) or return abort($switch->{switchname}, $cisco);
	
		info($switch->{switchname}, "Running STP config.");
		telnet_print($switch, $dlink, $cisco, "config stp version mstp")
			or return abort($switch->{switchname}, $cisco, $dlink);
		telnet_print($switch, $dlink, $cisco, "config stp priority 61440 instance_id 0")
			or return abort($switch->{switchname}, $cisco, $dlink);
		telnet_print($switch, $dlink, $cisco, "config stp ports 1:(1-44) edge true")
			or return abort($switch->{switchname}, $cisco, $dlink);
		telnet_print($switch, $dlink, $cisco, "enable lldp")
			or return abort($switch->{switchname}, $cisco, $dlink);
	
		info($switch->{switchname}, "Setting IP address.");
		telnet_print($switch, $dlink, $cisco, "config ipif System ipaddress $switch->{ipv4address}/$dlink_prefix vlan default")
			or return abort($switch->{switchname}, $cisco, $dlink);
	
		info($switch->{switchname}, "Closing D-Link link.");
		$dlink->close;

		info($switch->{switchname}, "Configuring IP on gateway.");
		telnet_cmd($switch, $cisco, "conf t")
			or return abort($switch->{switchname}, $cisco);
		telnet_cmd($switch, $cisco, "default int $dlink_port")
			or return abort($switch->{switchname}, $cisco);
		telnet_cmd($switch, $cisco, "int $dlink_port")
			or return abort($switch->{switchname}, $cisco);
		telnet_cmd($switch, $cisco, "no switchport")
			or return abort($switch->{switchname}, $cisco);
		telnet_cmd($switch, $cisco, "ip address $switch->{ipv4gateway} $switch->{netmask}")
			or return abort($switch->{switchname}, $cisco);
		# 'no shut'-patrol reporting in!
		telnet_cmd($switch, $cisco, "no shut")
			or return abort($switch->{switchname}, $cisco);
		telnet_cmd($switch, $cisco, "end")
			or return abort($switch->{switchname}, $cisco);

		# Wait for network convergence
		info($switch->{switchname}, "Waiting for network to converge.");
		unless (cisco_ping($cisco, $switch->{ipv4address}, 60, $switch->{coreswos})) {
			reset_interfaces($switch, $cisco)
				or return abort($switch->{switchname}, $cisco);
			$cisco->close;
			return error($switch->{switchname}, "Can't ping $switch->{switchname} on $switch->{ipv4address}, aborting.");
		}

		# Do it again!
		info($switch->{switchname}, "D-Link config phase 2.");
		$dlink = dlink_login($switch, $switch->{ipv4address}, '', $dlink_port) or return abort($switch->{switchname}, $cisco);

		info($switch->{switchname}, "Setting default route on switch. Saving config.");
		telnet_print($switch, $dlink, $cisco, "create iproute default $switch->{ipv4gateway}")
			or return abort($switch->{switchname}, $cisco, $dlink);
		telnet_print($switch, $dlink, $cisco, "save", 0)
			or return abort($switch->{switchname}, $cisco, $dlink);
		telnet_print($switch, $dlink, $cisco, "Y")
			or return abort($switch->{switchname}, $cisco, $dlink);
		telnet_print($switch, $dlink, $cisco, "logout")
			or return abort($switch->{switchname}, $cisco, $dlink);
		
		info($switch->{switchname}, "Closing D-Link link.");
		$dlink->close;
	}
	
	unless($skipped_port_only){
		# Configure final IOS stuff
		info($switch->{switchname}, "Final IOS config phase. Setting up all interfaces + Port-Channel.");

		# Reset interfaces
		reset_interfaces($switch, $cisco)
			or return abort($switch->{switchname}, $cisco);
		
		telnet_cmd($switch, $cisco, "conf t")
			or return abort($switch->{switchname}, $cisco);

		# this needs to be done on IOS-XE
		# Portchannel needs to exist before we can assign interfaces to it
		telnet_cmd($switch, $cisco, "int Po$switch->{etherchannel}")
			or return abort($switch->{switchname}, $cisco);
				
		# Rest of the config
		my $etherchan_desc;
		foreach my $port (@{$switch->{ports}}){
			telnet_cmd($switch, $cisco, "int $port")
				or return abort($switch->{switchname}, $cisco);
			telnet_cmd($switch, $cisco, "no switchport")
				or return abort($switch->{switchname}, $cisco);
			# 'no shut'-patrol reporting in!
			telnet_cmd($switch, $cisco, "no shut")
				or return abort($switch->{switchname}, $cisco);
			telnet_cmd($switch, $cisco, "desc D-Link $switch->{switchname}; RJ-45; 1G;")
				or return abort($switch->{switchname}, $cisco);
			telnet_cmd($switch, $cisco, "channel-group $switch->{etherchannel} mode passive")
				or return abort($switch->{switchname}, $cisco);
		
			# add port to descr
			$etherchan_desc .= "$port; ";
		}
		
		telnet_cmd($switch, $cisco, "int Po$switch->{etherchannel}")
			or return abort($switch->{switchname}, $cisco);
		telnet_cmd($switch, $cisco, "desc D-Link $switch->{switchname}; $etherchan_desc")
			or return abort($switch->{switchname}, $cisco);
		telnet_cmd($switch, $cisco, "ip address $switch->{ipv4gateway} $switch->{netmask}")
			or return abort($switch->{switchname}, $cisco);
	
		# ipv6-stuff
		unless (is_nx($switch->{coreswos})){
			# IOS
			telnet_cmd($switch, $cisco, "ipv6 enable")
				or return abort($switch->{switchname}, $cisco);
		}
	
		telnet_cmd($switch, $cisco, "ipv6 address $switch->{ipv6address}")
			or return abort($switch->{switchname}, $cisco);
	
		if (is_nx($switch->{coreswos})){
			telnet_cmd($switch, $cisco, "ip dhcp relay address $dhcprelay4_pri")
				or return abort($switch->{switchname}, $cisco);
		
			# define secondary if present
			if (defined($dhcprelay4_sec) && $dhcprelay4_sec){
				telnet_cmd($switch, $cisco, "ip dhcp relay address $dhcprelay4_sec")
					or return abort($switch->{switchname}, $cisco);
			}
		} else {
			# IOS
			telnet_cmd($switch, $cisco, "ip helper-address $dhcprelay4_pri")
				or return abort($switch->{switchname}, $cisco);
		
			# define secondary if present
			if (defined($dhcprelay4_sec) && $dhcprelay4_sec){
				telnet_cmd($switch, $cisco, "ip helper-address $dhcprelay4_sec")
					or return abort($switch->{switchname}, $cisco);
			}
		}
	
		# Custom Portchannel-config
		# Dynamically applied depending on OS
		foreach my $cmd (@{$po_config->{$switch->{coreswos}}}){
			telnet_cmd($switch, $cisco, $cmd)
				or return abort($switch->{switchname}, $cisco);
		}
		
		# 'no shut'-patrol reporting in!
		telnet_cmd($switch, $cisco, "no shut")
		 	or return abort($switch->{switchname}, $cisco);
		telnet_cmd($switch, $cisco, "end")
			or return abort($switch->{switchname}, $cisco);
	}
	
	# If we skipped last port at the start, we configure it now
	if (($skip_last_port && $skipped_port && defined($skipped_port)) || ($skipped_port_only && defined($skipped_port_only))){
		if ($skipped_port_desc_only){
			info($switch->{switchname}, "Configuring skipped port... (description only)");
		} else {
			info($switch->{switchname}, "Configuring skipped port...");
		}
		
		telnet_cmd($switch, $cisco, "conf t")
			or return abort($switch->{switchname}, $cisco);
		unless ($skipped_port_desc_only){
			telnet_cmd($switch, $cisco, "default int $skipped_port")
				or return abort($switch->{switchname}, $cisco);
		}
		
		telnet_cmd($switch, $cisco, "int $skipped_port")
			or return abort($switch->{switchname}, $cisco);
		telnet_cmd($switch, $cisco, "desc AP \@ D-Link $switch->{switchname}; RJ-45; 1G;")
			or return abort($switch->{switchname}, $cisco);
		
		unless ($skipped_port_desc_only){
			foreach my $cmd (@{$last_port_config->{$switch->{coreswos}}}){
				telnet_cmd($switch, $cisco, $cmd)
					or return abort($switch->{switchname}, $cisco);
			}
			# 'no shut'-patrol reporting in!
			telnet_cmd($switch, $cisco, "no shut")
			 	or return abort($switch->{switchname}, $cisco);
		}
		telnet_cmd($switch, $cisco, "end")
			or return abort($switch->{switchname}, $cisco);
	}
	
	# If only cisco-config
	if($cisco_config){
		log_it("CONFIG", "green", $switch->{switchname}, "Cisco-config relevant to switch '$switch->{switchname}' ($switch->{ipv4address}) done! \\o/");
	}

	# Check if all is OK, but not if configuring skipped port only
	my $return = 0;
	if ($skipped_port_only){
		info($switch->{switchname}, "Done doing skipped port config. Not checking if anything is online.");
		$return = 1;
	} else {
		unless (pong($switch->{ipv4address}, 15)){
			if (cisco_ping($cisco, $switch->{ipv4address}, 60, $switch->{coreswos})) {
				# we can reach from core, but not from other places, lets warn
				log_it("ERROR", "red", $switch->{switchname}, "Switch $switch->{switchname} reachable only from core/distro.");
			} else {
				reset_interfaces($switch, $cisco)
					or return abort($switch->{switchname}, $cisco);
				$cisco->close;
				return error($switch->{switchname}, "Can't ping $switch->{switchname} on $switch->{ipv4address}, aborting.");
			}
		} else {
			# pingable, OK
			log_it("SUCCESS", "green", $switch->{switchname}, "Switch $switch->{switchname} ($switch->{ipv4address}) set up! \\o/");	

			$return = 1;
			
			# push template-config to D-Link if template-file is given as argument
			if($dlink_config){
				info($switch->{switchname}, "Going to push D-Link template config to switch $switch->{switchname} ($switch->{ipv4address})");
				$return = push_dlink_template_config($switch);
			}
		}
	}
	
	if($save_config){
		# save the cisco-config
		info($switch->{switchname}, "Saving config on core-switch ($switch->{coreswip}).");
		telnet_cmd($switch, $cisco, "write")
			or return abort($switch->{switchname}, $cisco);
	}
	
	$cisco->close;
	return $return;
}

# Process switches
sub process_switches {
	while (my $switch = $switchq->dequeue()){
		last if ($switch eq 'DONE');	# all done
		
		my $time_start = time();
		
		# Wait till there is sessions/VTYs available
		while (1){
			$telnet_sessions{$switch->{coreswip}} = 0 unless $telnet_sessions{$switch->{coreswip}};
			$telnet_sessions{$switch->{coreswip}} += 2;

			if ($telnet_sessions{$switch->{coreswip}} <= $os_info->{$switch->{coreswos}}{max_sessions}){
				# lower or equal to max_sessions on current switch
				# lets move on
				last;
			} else {
				# we would exceed max_sessions on current switch
				# we wait until there is free sessions
				info($switch->{switchname}, "There are no more free sessions left on '$switch->{coreswip}' ($switch->{coreswos}). Waiting...");
				$telnet_sessions{$switch->{coreswip}} -= 2;
				sleep (int(rand(10)) + 10);
			}
		}

		info($switch->{switchname}, "Number of sessions on switch '$switch->{coreswip}': $telnet_sessions{$switch->{coreswip}}.");

		if (setup($switch)) {
			# Count number of switches
			$switches++;
			
		} else {
			log_it("FAILED", "red", $switch->{switchname}, "Configuring $switch->{switchname} failed.");
			
			# Count failed switches
			$failed_switches++;
		}
		
		# Remove session
		$telnet_sessions{$switch->{coreswip}} -= 2;
		
		# Summarize total time spent, used to calculate average per switch
		$total_time += time() - $time_start;
	}
	
  	# detach thread -- we're done
	threads->detach;
}

# Let's start
my $time_start = time();
log_it("INFO", "yellow", "dlink-ng", "Starting dlink-ng with $max_threads threads...");
log_it("INFO", "yellow", "dlink-ng", "Configured to skip last port on all switches.") if $skip_last_port;

# Let's add all switches to the queue
while (<STDIN>){
	next if /^(.*#|\s+$)/;	# skip if comment, or blank line
	
	my ($switchname, $coreswip, $etherchannel, $cidr, $ipv4address, $ipv4gateway, $ipv6address, @ports) = split;
	
	# skip if less than 1 port is provided
	if (scalar(@ports) < 1){
		log_it("FAILED", "red", $switchname, "Switch '$switchname' had less than 1 port configured. Skipping.");
		next;
	}
	
	# define OS of the coresw
	my $coreswos = set_coreswos($switchname);
	
	# find netmask
	my $netmask = Net::IP->new($cidr)->mask();

	my %switch = (
		switchname => $switchname,
		coreswip => $coreswip,
		coreswos => $coreswos,
		etherchannel => $etherchannel,
		ipv4address => $ipv4address,
		ipv4gateway => $ipv4gateway,
		netmask => $netmask,
		ipv6address => $ipv6address,
		ports => \@ports,
	);

	# Only configure a single switch?
	if (defined $single_switch){
		unless ($single_switch eq $switchname){
			next;
		}
	}
	
	# Add switch to queue
	$switchq->enqueue(\%switch);
}

# Let the threads know when they're done
$switchq->enqueue("DONE") for (1..$max_threads);

# Start processing the queue
threads->create("process_switches") for (1..$max_threads);

# Wait till all threads is done
sleep 5 while (threads->list(threads::running));

# If 0 switches
my $runtime = time() - $time_start;
my $total_switches = $switches + $failed_switches;
if($total_switches == 0){
	log_it("INFO", "yellow", "dlink-ng", "Finished!");
	log_it("INFO", "yellow", "dlink-ng", "Crunched 0 switches in $runtime seconds.");
	exit 1;
}

# Done
my $avg = sprintf("%.1f", $total_time / $total_switches);
log_it("INFO", "yellow", "dlink-ng", "Finished!");
log_it("INFO", "yellow", "dlink-ng", "Crunched $total_switches switches in $runtime seconds.");
log_it("INFO", "yellow", "dlink-ng", "$switches of these were successful, while $failed_switches failed.");
log_it("INFO", "yellow", "dlink-ng", "Average of $avg seconds per switch.");


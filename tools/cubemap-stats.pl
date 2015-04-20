#!/usr/bin/perl
use strict;
use warnings;
use POSIX qw(strftime);
use NetAddr::IP;
use Net::IP;

my (%streams, %ips, %total);
$total{count}{c} = 0;
$total{unique_count}{c} = 0;
$total{count}{int} = 0;
$total{unique_count}{int} = 0;
$total{count}{ext} = 0;
$total{unique_count}{ext} = 0;

sub stream_name {
	my $stream = shift;
	$stream =~ s/\///g;
	return $stream;
}

# Is client in the network?
sub is_in_network{
	my ($ip, $ipv4, $ipv6) = @_;
	my $in_scope = 0;
	my $ipv4_range = NetAddr::IP->new($ipv4);
	my $ipv6_range = NetAddr::IP->new($ipv6);
	
	if (Net::IP->new($ip)->ip_is_ipv4()){
		if (NetAddr::IP->new($ip)->within($ipv4_range)){
			$in_scope = 1;
		}
	} else {
		if (NetAddr::IP->new($ip)->within($ipv6_range)){
			$in_scope = 1;
		}
	}
	
	return $in_scope;
}

# add count
sub add_count{
	my ($date, $stream_name, $count_name, $count_type) = @_;

	if($streams{$date}{$stream_name}{$count_name}{$count_type}){
		$streams{$date}{$stream_name}{$count_name}{$count_type}++;
	} else {
		$streams{$date}{$stream_name}{$count_name}{$count_type} = 1;
	}
}

sub print_info{
	foreach my $date (sort keys %streams) {
		print "### $date\n";
		foreach my $stream (sort keys %{$streams{$date}}){
			my $stream_name = stream_name($stream);
			printf "\t%s: %s (%s) - Int: %s (%s), Ext: %s (%s)\n",
				$stream_name,
				$streams{$date}{$stream}{count}{c},
				$streams{$date}{$stream}{unique_count}{c},
				$streams{$date}{$stream}{count}{int},
				$streams{$date}{$stream}{unique_count}{int},
				$streams{$date}{$stream}{count}{ext},
				$streams{$date}{$stream}{unique_count}{ext},
		}
	}
	print "\n\nTotal: $total{count}{c} ($total{unique_count}{c})\n";
	print "Internal: $total{count}{int} ($total{unique_count}{int})\n";
	print "External: $total{count}{ext} ($total{unique_count}{ext})\n";
}

while (<STDIN>) {
	chomp;
	my ($epoch, $ip, $stream, $connected_time, $bytes_sent, $loss_bytes, $loss_events) = /^(\d+) (\S+) (\S+) (\d+) (\d+) (\d+) (\d+)/ or next;

	next if ($stream =~ m/-/);
	next if ($stream =~ m/test/);
	
	my $stream_name = stream_name($stream);
	
	my $date = strftime("%d %b %Y", localtime($epoch));

	my $internal = is_in_network($ip, '151.216.128.0/17', '2a02:ed02::/32');
	unless($internal){
		# check server /24
		$internal = is_in_network($ip, '185.12.59.0/24', '2a02:ed02::/32');
	}
	
	print "$date, $stream_name, $ip, $internal\n";

	if($ips{$date}{$ip}){
		# already viewed this day

		add_count($date, $stream_name, 'count', 'c');

		if($internal){
			add_count($date, $stream_name, 'count', 'int');
			$total{count}{int}++;
		} else {
			add_count($date, $stream_name, 'count', 'ext');
			$total{count}{ext}++;	
		}
		
		$total{count}{c}++;
	} else {
		# not viewed this day
		$ips{$date}{$ip} = 1;
		
		add_count($date, $stream_name, 'count', 'c');
		add_count($date, $stream_name, 'unique_count', 'c');
		
		if($internal){
			add_count($date, $stream_name, 'count', 'int');
			add_count($date, $stream_name, 'unique_count', 'int');
			$total{count}{int}++;
			$total{unique_count}{int}++;
		} else {
			add_count($date, $stream_name, 'count', 'ext');
			add_count($date, $stream_name, 'unique_count', 'ext');
			$total{count}{ext}++;
			$total{unique_count}{ext}++;
		}

		$total{count}{c}++;
		$total{unique_count}{c}++;
	}
}

print_info();
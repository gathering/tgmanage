#! /usr/bin/perl
use strict;
use warnings;
use POSIX qw(strftime);

my $stats_filename = "/Users/jocke/Desktop/cubemap-tg15-access.log";

my (%streams, %ips);
my $total = 0;
my $unique = 1;

open my $stats, "<", $stats_filename
	or die "$stats_filename: $!";
while (<$stats>) {
	chomp;
	my ($epoch, $ip, $stream, $connected_time, $bytes_sent, $loss_bytes, $loss_events) = /^(\d+) (\S+) (\S+) (\d+) (\d+) (\d+) (\d+)/ or next;
	
	my $stream_name = stream_name($stream);
	
	my $date = strftime("%d %b %Y", localtime($epoch));
	
	if($unique){
		if($ips{$date}{$ip}){
			# already viewed this day, skip
			next;
		} else {
			# not viewed this day, add
			$ips{$date}{$ip} = 1;
			
			if($streams{$date}{$stream_name}{count}){
				$streams{$date}{$stream_name}{count}++;
			} else {
				$streams{$date}{$stream_name}{count} = 1;
			}
			$total++;
		}
	} else {
		if($streams{$date}{$stream_name}{count}){
			$streams{$date}{$stream_name}{count}++;
		} else {
			$streams{$date}{$stream_name}{count} = 1;
		}
		$total++;
	}
}
close $stats;

foreach my $date (sort keys %streams) {
	print "### $date\n";
	foreach my $stream (sort keys %{$streams{$date}}){
		next if ($stream =~ m/-/);
		next if ($stream =~ m/test/);
		my $stream_name = stream_name($stream);
		print "\t$stream_name: $streams{$date}{$stream}{count}\n";
	}
}
print "\n\nTotal: $total\n";

sub stream_name {
	my $stream = shift;
	$stream =~ s/\///g;
	return $stream;
}

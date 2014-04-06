#!/usr/bin/perl
use warnings;
use strict;
use lib '../../include';
use POSIX;

my $delaytime = 30;
my $poll_frequency = 60;

sub mylog {
	my $msg = shift;
	my $time = POSIX::ctime(time);
	$time =~ s/\n.*$//;
	printf STDERR "[%s] %s\n", $time, $msg;
}

if ($#ARGV != 1) {
	die("Error in arguments passed\n".
	       "./ssendfile.pl addr configfile\n");
}

my $conn = nms::switch_connect($ARGV[0]);
if (!defined($conn)) {
	die("Could not connect to switch.\n");
}

open(CONFIG, $ARGV[1]);
while (<CONFIG>) {
	my $cmd = $_;
	$cmd =~ s/[\r\n]+//g;
	print "Executing: `$cmd`\n";
#	if ($cmd =~ /ip ifconfig swif0 (\d{1-3}\.\d{1-3}\.\d{1-3}\.\d{1-3})/) {
#		print "New ip: $1\n";
#		$conn->cmd(	String => $cmd,
#				Timeout => 3);
#		$conn = nms::switch_connect($1);
#		if (!defined($conn)) {
#			die "Could not connect to new ip: $1\n";
#		}
#	}
#	else {
		my @data = nms::switch_exec($cmd, $conn);
		foreach my $line (@data) {
			$line =~ s/[\r\n]+//g;
			print "$line\n";
		}
#	}
}

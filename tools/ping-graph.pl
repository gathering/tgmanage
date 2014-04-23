#! /usr/bin/perl

# Makes latency-against-time graphs, one per switch.

use warnings;
use strict;
use DBI;
use lib '../include';
use nms;

BEGIN {
	require "../include/config.pm";
	eval {
		require "../include/config.local.pm";
	};
}

my $dbh = db_connect();
my $switches = $dbh->selectall_hashref('SELECT sysname,switch FROM switches ORDER BY sysname', 'sysname');
if (0) {
	my %switchfds = ();
	while (my ($sysname, $switch) = each %$switches) {
		print "$sysname -> $switch->{switch}\n";
		open my $fh, ">", "$sysname.txt"
			or die "$sysname.txt: $!";
		$switchfds{$switch->{'switch'}} = $fh;
	}	

	my $q = $dbh->prepare('SELECT switch,EXTRACT(EPOCH FROM updated),latency_ms FROM ping');
	$q->execute;

	my $i = 0;
	while (my $ref = $q->fetchrow_arrayref) {
		next if (!defined($ref->[2]));
		my $fh = $switchfds{$ref->[0]};
		next if (!defined($fh));
		print $fh $ref->[1], " ", $ref->[2], "\n";
		if (++$i % 1000000 == 0) {
			printf "%dM records...\n", int($i / 1000000);
		}
	}

	while (my ($sysname, $switch) = each %$switches) {
		close $switchfds{$switch->{'switch'}};
	}
}

while (my ($sysname, $switch) = each %$switches) {
	print "$sysname -> $switch->{switch}\n";
	open my $gnuplot, "|-", "gnuplot"
		or die "gnuplot: $!";
	print $gnuplot <<"EOF";
set timefmt "%s"
set xdata time
set format x "%d/%m %H:%M"
set term png size 1280,720
set output '$sysname.png'
set yrange [0:200]
plot "$sysname.txt" using (int(\$1)):2 ps 0.1
EOF
	close $gnuplot;
}

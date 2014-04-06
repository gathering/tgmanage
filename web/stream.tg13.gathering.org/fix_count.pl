#! /usr/bin/perl

my $lines = {};

open LOG, "<", "/home/techserver/count_datacube.log"
	or die "count_datacube.log: $!";

while (<LOG>) {
	chomp;
	my ($date, $port, $proto, $audience, $count) = split /\s+/;
	my $key = $port . ' ' . $proto . ' ' . $audience;
	$lines->{$date}{$key} = $count;
}

close LOG;

my $last_date = undef;
for my $date (sort keys %$lines) {
	for my $key (keys %{$lines->{$date}}) {
		if (defined($last_date) && !exists($lines->{$last_date}{$key})) {
			$lines->{$last_date}{$key} = $lines->{$date}{$key};
		}
	}
	$last_date = $date;
}

for my $date (sort keys %$lines) {
	for my $key (sort keys %{$lines->{$date}}) {
		print "$date $key " . $lines->{$date}{$key} . "\n";
	}
}

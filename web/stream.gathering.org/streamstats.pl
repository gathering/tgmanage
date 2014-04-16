#! /usr/bin/perl
use strict;
use warnings;
use POSIX;
use CGI qw(fatalsToBrowser);
	
my %port_spec = prepare_spec(CGI::param('port'));
my %proto_spec = prepare_spec(CGI::param('proto'));
my %audience_spec = prepare_spec(CGI::param('audience'));

#open LOG, "<", "/home/techserver/count_datacube.log"
open LOG, "-|", "/home/techserver/fix_count.pl"
#open LOG, "<", "/home/techserver/cleaned_datacube.log"
	or die "count_datacube.log: $!";

our %desc = (
	3013 => 'main (3013)',
	3014 => 'main-sd (3014)',
	3015 => 'webcam (3015)',
	3016 => 'webcam-south (3016)',
	3017 => 'webcam-south-transcode (3017)',
	3018 => 'webcam-fisheye (3018)',
	5013 => 'main-transcode (5013)',
	5015 => 'webcam-transcode (5015)',
);

my $lines = {};
my %streams = ();

while (<LOG>) {
	chomp;
	my ($date, $port, $proto, $audience, $count) = split /\s+/;
	next if (filter($port, $proto, $audience));
	my $stream_id = get_stream_id($port, $proto, $audience);
	$streams{$stream_id} = 1;
	$lines->{$date}{$stream_id} += $count;
}

close LOG;

print CGI::header(-type=>'image/png');

my $tmpfile = POSIX::tmpnam();
open GRAPH, ">", $tmpfile
	or die "$tmpfile: $!";
for my $date (sort keys %$lines) {
	my @cols = ();
	for my $stream (keys %streams) {
		push @cols, ($lines->{$date}{$stream} // "0");
	}
	print GRAPH "$date ", join(' ', @cols), "\n";
}
close GRAPH;

my $tmpfile2 = POSIX::tmpnam();
open GNUPLOT, ">", $tmpfile2
	or die "$tmpfile2: $!";
print GNUPLOT "set terminal png\n";
print GNUPLOT "set xdata time\n";
print GNUPLOT "set timefmt \"20%y-%m-%d-%H:%M:%S\"\n";
print GNUPLOT "set xtics axis \"2000-00-00-01:00:00\"\n";
print GNUPLOT "set format x \"%H\"\n";

my @plots = ();
my $idx = 2;
for my $stream (keys %streams) {
	push @plots, "\"$tmpfile\" using 1:$idx title \"$stream\" with lines";
	++$idx;
}
print GNUPLOT "plot ", join(', ', @plots);

# \"$tmpfile\" using 0:2 with lines, \"$tmpfile\" using 0:3 with lines\n";
close GNUPLOT;

system("gnuplot < $tmpfile2");

sub prepare_spec {
	my $spec = shift;
	return () if ($spec eq 'compare' || $spec eq 'dontcare');
	$spec =~ s/^compare://;

	my %ret = ();
	for my $s (split /,/, $spec) {
		$ret{$s} = 1;
	}
	return %ret;
}

sub filter {
	my ($port, $proto, $audience) = @_;
	return 1 if (filter_list(\%port_spec, $port));
	return 1 if (filter_list(\%proto_spec, $proto));
	return 1 if (filter_list(\%audience_spec, $audience));
	return 0;
}

sub filter_list {
	my ($spec, $candidate) = @_;
	return 0 if ((scalar keys %$spec) == 0);
	return !exists($spec->{$candidate});
}	

sub get_stream_id {
	my ($port, $proto, $audience) = @_;
	my @keys = ();
	if (CGI::param('port') =~ /^compare/) {
		if (exists($desc{$port})) {
			push @keys, $desc{$port};
		} else {
			push @keys, "___" . $port . "___";
		}
	}
	push @keys, $proto if (CGI::param('proto') =~ /^compare/);
	push @keys, $audience if (CGI::param('audience') =~ /^compare/);
	return join(',', @keys);
}

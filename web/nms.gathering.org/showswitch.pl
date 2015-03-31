#! /usr/bin/perl
use CGI;
use DBI;
use Time::HiRes;
use POSIX ":sys_wait_h";
use strict;
use warnings;
use lib '../../include';
use nms;
use File::Basename;
my $cgi = CGI->new;
my $cwd = dirname($0);
my $switch = $cgi->param('id');
my $width = $cgi->param('width');
my $height = $cgi->param('height');
my @pids = ();
my $resthtml = "";

$width = 500 unless (defined($width));
$height = 250 unless (defined($height));

require "$cwd/mygraph.pl";

my $start = [Time::HiRes::gettimeofday];
my $dbh = nms::db_connect();

# Fetch the name
my $ref = $dbh->selectrow_hashref('SELECT sysname,ip FROM switches WHERE switch=?', undef, $switch);

print $cgi->header(-type=>'text/html; charset=utf-8');
print <<"EOF";
<html>
  <head>
    <title>snmp</title>
  </head>
  <body>
    <h1>Switch $switch ($ref->{'sysname'} - $ref->{'ip'})</h1>
EOF

my $q = $dbh->prepare('select port,coalesce(description, \'Port \' || port) as description,extract(epoch from time) as time,bytes_in,bytes_out from switches natural left join portnames natural join polls where time between now() - \'1 day\'::interval and now() and switch=? order by switch,port,time;') or die $dbh->errstr;
$q->execute($switch) or die $dbh->errstr;

my (@totx, @toty1, @toty2) = ();

my (@x, @y1, @y2) = ();
my $last_port = -1;
my $portname = "";
my $min_x = time;
my $max_x = time - 86400;
my ($min_y, $max_y, $prev_time, $prev_in, $prev_out);
my ($if,$of,$ifv,$ofv);
my $idx;
my ($min_ty,$max_ty) = (0, 10_000_000/8);

$prev_time = -1;
my $last_totx;
while (my $ref = $q->fetchrow_hashref()) {
	my $time = $ref->{'time'};
	my $in = $ref->{'bytes_in'};
	my $out = $ref->{'bytes_out'};
	next if ($time == $prev_time);
	if ($ref->{'port'} != $last_port) {
		if ($last_port != -1) {
			my $filename = "$switch-$last_port-$width-$height.png";

			# reap children
			waitpid(-1, WNOHANG);

			my $pid = fork();
			if ($pid == 0) {
# write out the graph
				my $graph = makegraph($width, $height, $min_x, $max_x, $min_y, $max_y, 5);
				plotseries($graph, \@x, \@y1, 255, 0, 0, $min_x, $max_y);
				plotseries($graph, \@x, \@y2, 0, 0, 255, $min_x, $max_y);

				open GRAPH, ">$cwd/img/$filename"
					or die "$cwd/img/$filename: $!";
				print GRAPH $graph->png;
				close GRAPH;
				exit;
			}

			push @pids, $pid;

			$resthtml .= "<div style=\"float: left;\"><h2>$portname</h2>\n";
			$resthtml .= "<p><img src=\"img/$filename\" width=\"$width\" height=\"$height\" /></p></div>\n";
		}
	
		# Reset all the variables
		@x = ();
		@y1 = ();
		@y2 = ();
		($min_y,$max_y) = (0, 10_000_000/8);
		$prev_time = $ref->{'time'};
		$prev_in = $ref->{'bytes_in'};
		$prev_out = $ref->{'bytes_out'};
		$last_port = $ref->{'port'};
		$portname = $ref->{'description'};
		($if,$of,$ifv,$ofv) = (0,0,0,0);
		($prev_time,$prev_in,$prev_out) = ($time,$in,$out);
		$idx = 0;
		$last_totx = undef;
		next;
	}

	# Assume overflow (unless the switch has been down for >10 minutes)
	my ($calc_in, $calc_out) = ($in, $out);
	if ($in < $prev_in || $out < $prev_out) {
		if ($prev_in < 4294967296 && $prev_out < 4294967296) {
			# ick, heuristics
			if ($prev_time - $time > 600 || ($in + 4294967296 - $prev_in) > 2147483648 || ($out + 4294967296 - $prev_out) > 2147483648) {
				($prev_time,$prev_in,$prev_out) = ($time,$in,$out);
				next;
			}

			$calc_in += 4294967296 if ($in < $prev_in);
			$calc_out += 4294967296 if ($out < $prev_out);
		} else {
			$prev_in = 0;
			$prev_out = 0;
		}
	}

	# Remove dupes
	if ($in == $prev_in && $out == $prev_out) {
		($prev_time,$prev_in,$prev_out) = ($time,$in,$out);
		next;
	}

	# Find the current flow
	my $if = ($calc_in - $prev_in) / ($time - $prev_time);
	my $of = ($calc_out - $prev_out) / ($time - $prev_time);

	# Summarize (we don't care about the summed variance for now)	
        $min_x = $time if (!defined($min_x) || $time < $min_x);
        $max_x = $time if (!defined($max_x) || $time > $max_x);
	$min_y = $if if (!defined($min_y) || $if < $min_y);
	$min_y = $of if ($of < $min_y);
	$max_y = $if if (!defined($max_y) || $if > $max_y);
	$max_y = $of if ($of > $max_y);

	my $pt = 0.5 * ($time + $prev_time);

	push @x, $pt;
	push @y1, $if;
	push @y2, $of;

	while ($idx < $#totx && $pt > $totx[$idx]) {
		++$idx;
	}
	if ($idx >= $#totx) {
		push @totx, $pt;
		push @toty1, $if;
		push @toty2, $of;
		++$idx;

		$min_ty = $if if (!defined($min_ty) || $if < $min_ty);
		$min_ty = $of if ($of < $min_ty);
		$max_ty = $if if (!defined($max_ty) || $if > $max_ty);
		$max_ty = $of if ($of > $max_ty);
	} else {
		if (!defined($last_totx) || $last_totx != $idx) {
			$toty1[$idx] += $if;
			$toty2[$idx] += $of;
		}
		$last_totx = $idx;

		$min_ty = $toty1[$idx] if (!defined($min_ty) || $toty1[$idx] < $min_ty);
		$min_ty = $toty2[$idx] if ($toty2[$idx] < $min_ty);
		$max_ty = $toty1[$idx] if (!defined($max_ty) || $toty1[$idx] > $max_ty);
		$max_ty = $toty2[$idx] if ($toty2[$idx] > $max_ty);
	}
	
	($prev_time,$prev_in,$prev_out) = ($time,$in,$out);
}
$dbh->disconnect;

# last graph
my $filename = "$switch-$last_port-$width-$height.png";

my $pid = fork();
if ($pid == 0) {
	my $graph = makegraph($width, $height, $min_x, $max_x, $min_y, $max_y, 5);
	plotseries($graph, \@x, \@y1, 255, 0, 0, $min_x, $max_y);
	plotseries($graph, \@x, \@y2, 0, 0, 255, $min_x, $max_y);

	open GRAPH, ">$cwd/img/$filename"
	or die "img/$filename: $!";
	print GRAPH $graph->png;
	close GRAPH;
	exit;
}

push @pids, $pid;

$resthtml .= "<div style=\"float: left;\"><h2>$portname</h2>\n";
$resthtml .= "<p><img src=\"img/$filename\" width=\"$width\" height=\"$height\" /></p></div>\n";
		
# total graph
my $graph = makegraph($width, $height, $min_x, $max_x, $min_ty, $max_ty, 5);
plotseries($graph, \@totx, \@toty1, 255, 0, 0, $min_x, $max_ty);
plotseries($graph, \@totx, \@toty2, 0, 0, 255, $min_x, $max_ty);

$filename = "$switch-$width-$height.png";
open GRAPH, ">$cwd/img/$filename" or die "img/$filename: $!";
print GRAPH $graph->png;
close GRAPH;

# Wait for all the other graphs to be done
while (waitpid(-1, 0) != -1) {
	1;
}

print $resthtml;

print "<div style=\"float: left;\"><h2>Total</h2>\n";
print "<p><img src=\"img/$filename\" width=\"$width\" height=\"$height\" /></p></div>\n";

my $elapsed = Time::HiRes::tv_interval($start); 
printf "<p style=\"clear: both;\">Page and all graphs generated in %.2f seconds.</p>\n", $elapsed;
print "</body>\n</html>\n";

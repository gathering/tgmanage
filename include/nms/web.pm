#! /usr/bin/perl
# vim:ts=8:sw=8
use strict;
use warnings;
use utf8;
use DBI;
use Data::Dumper;
use JSON;
use nms;
use Digest::SHA;
use FreezeThaw;
use URI::Escape;
package nms::web;

use base 'Exporter';
our %get_params;
our %json;
our @EXPORT = qw(finalize_output json $dbh db_safe_quote %get_params get_input %json);
our $dbh;
our $now;
our $when;
our %cc;

sub get_input {
	my $in = "";
	while(<STDIN>) { $in .= $_; }
	return $in;
}
# Print cache-control from %cc
sub printcc {
	my $line = "";
	my $first = "";
	foreach my $tmp (keys(%cc)) {
		$line .= $first . $tmp . "=" . $cc{$tmp};
		$first = ", ";
	}
	print 'Cache-Control: ' . $line . "\n";
}

sub db_safe_quote {
	my $word = $_[0];
	my $term = $get_params{$word};
	if (!defined($term)) {
		if(defined($_[1])) {
			$term = $_[1];
		} else {
			die "Missing CGI param $word";
		}
	}
	return $dbh->quote($term) || die;
}

# returns a valid $when statement
# Also sets cache-control headers if time is overridden
sub setwhen {
	my $when;
	$now = "now()";
	if (defined($get_params{'now'})) {
		$now = db_safe_quote('now') . "::timestamp ";
		$cc{'max-age'} = "3600";
	}
	$when = " time > " . $now . " - '15m'::interval and time < " . $now . " ";
	return $when;
}

sub finalize_output {
	my $query;
	my $hash = Digest::SHA::sha512_base64(FreezeThaw::freeze(%json));
	$dbh->commit;
	$query = $dbh->prepare('select to_char(' . $now . ', \'YYYY-MM-DD"T"HH24:MI:SS\') as time;');
	$query->execute();

	$json{'time'} = $query->fetchrow_hashref()->{'time'};
	$json{'hash'} = $hash;
	printcc;

	print "Content-Type: text/jso; charset=utf-8\n\n";
	print JSON::XS::encode_json(\%json);
	print "\n";
}

sub populate_params {
	my $querystring = $ENV{'QUERY_STRING'} || "";
	foreach my $hdr (split("&",$querystring)) {
		my ($key, $value) = split("=",$hdr,"2");
		$get_params{$key} = URI::Escape::uri_unescape($value);
	}
}

BEGIN {
	$cc{'stale-while-revalidate'} = "3600";
	$cc{'max-age'} = "20";

	$dbh = nms::db_connect();
	populate_params();
	$when = setwhen();
}
1;

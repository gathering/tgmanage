#! /usr/bin/perl
# vim:ts=8:sw=8

#use CGI qw(fatalsToBrowser);
use DBI;
use lib '../../include';
use nms;
use nms::web qw(%get_params %json finalize_output get_input);
use strict;
use warnings;
use JSON;
use Data::Dumper;

$nms::web::cc{'max-age'} = "0";

my $in = get_input();
my @tmp = @{JSON::XS::decode_json($in)};

my @added;
my @dups;

my $sth = $nms::web::dbh->prepare("SELECT sysname FROM switches WHERE sysname=?");
my $insert = $nms::web::dbh->prepare("INSERT INTO SWITCHES (ip, sysname, switchtype) VALUES(?,?,'ex2200');");

foreach my $tmp2 (@tmp) {
	my %switch = %{$tmp2};
	my $affected = 0;

	$sth->execute( $switch{'sysname'});
	while ( my @row = $sth->fetchrow_array ) {
		$affected += 1;
	}

	if ($affected == 0) {
		$insert->execute($switch{'mgtmt4'}, $switch{'sysname'});
		push @added, $switch{'sysname'};
	} else {
		push @dups, $switch{'sysname'};
	}
}
$json{'switches_addded'} = \@added;
$json{'switches_duplicate'} = \@dups;

finalize_output();

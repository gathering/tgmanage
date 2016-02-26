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
my %tmp = %{JSON::XS::decode_json($in)};

my $query = "INSERT INTO SWITCHES (ip, sysname, switchtype) VALUES('"
	. $tmp{'mgtmt4'} . "','"
	. $tmp{'name'} . "','ex2200');";

$json{'sql'} = $query;

my $q = $nms::web::dbh->prepare($query);
$q->execute() || die "foo";


finalize_output();

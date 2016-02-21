#! /usr/bin/perl
# vim:ts=8:sw=8
use lib '../../include';
use utf8;
use nms;
use nms::web;
use strict;
use warnings;

my $id = db_safe_quote('comment');
my $state = db_safe_quote('state');

my $q = $nms::web::dbh->prepare("UPDATE switch_comments SET state = " . $state . " WHERE id = " . $id . ";");
$q->execute();

$nms::web::cc{'max-age'} = '0';
$nms::web::cc{'stale-while-revalidate'} = '0';
$nms::web::json{'state'} = 'ok';

finalize_output();

#!/usr/bin/perl
use warnings;
use strict;

my $ignore = "((([0-9a-f]{2}[:]){5}[0-9a-f]{2})|";
$ignore .= "([0-9]{4}\-[0-9]{2}\-[0-9]{2} [0-9]{2}\:[0-9]{2}\:[0-9]{2})";
$ignore .= ").*";

my $community = "<removed>";

my $skip = 0;

open (SQL, $ARGV[0]) or die "Unable to open SQL-file";
while (<SQL>) {
	unless (/^$ignore$/){
		
		if (/COPY (mbd_log|squeue|temppoll|ap_poll)/){
			$skip = 1;
			print;
		}

		if (/\\\./){
			$skip = 0;
		}

		unless ($skip){
			s/$community/<removed>/g; # community
			s/PASSWORD '.+'/PASSWORD '<removed>'/g; # password for SQL-users
			s/public$/<removed>/; # public-community -- assuming last column
			print;
		}
	}
}

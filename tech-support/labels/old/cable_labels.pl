#!/usr/bin/perl
 
use strict;
use warnings;
 
my ($rows, $switches, $cables) = @ARGV;
 
for my $row (1 .. $rows) {
    next if (!($row & 1));
 
    for my $switch (1 .. $switches) {
        for my $cable (1 .. $cables) {
            print join('-', ($row, $switch, $cable)) . ';' . "\n";
        }
    }
}

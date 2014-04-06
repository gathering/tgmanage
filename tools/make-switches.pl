#! /usr/bin/perl
use strict;
use warnings;

my $switchtype = "dlink3100";

print "begin;\n";
print "delete from temppoll;\n";
print "delete from dhcp;\n";
print "delete from switches where switchtype = '$switchtype';\n";
#print "SELECT pg_catalog.setval('switches_switch_seq', 1, false);\n";
print "SELECT pg_catalog.setval('polls_poll_seq', 1, false);\n";

my %ip;
my $i = 1;
while (<STDIN>) {
	chomp;
	my @info = split(/ /);

	if (scalar @info < 5) {
		die "Unknown line: $_";
	}

	my $name = $info[0];
	my $range = $info[3];
	my $ip = $info[4];

	print "insert into switches (ip, sysname, switchtype) values ('$ip', '$name', '$switchtype');\n";
	print "insert into dhcp select switch, '$range' from switches where sysname = '$name';\n";
}
close HOSTS;

print "end;\n";

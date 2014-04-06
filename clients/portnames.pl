#! /usr/bin/perl

my ($host,$switchtype,$community) = @ARGV;

open SNMP, "snmpwalk -Os -c $community -v 2c $host ifDescr |"
	or die "snmpwalk: $!";

print "begin;\n";
print "delete from portnames where switchtype='$switchtype';\n";

while (<SNMP>) {
	chomp;
	/^ifDescr\.(\d+) = STRING: (.*)$/ or next;

	print "insert into portnames (switchtype,port,description) values ('$switchtype',$1,'$2 (port $1)');\n";
}

print "end;\n";

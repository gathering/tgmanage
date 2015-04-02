#!/usr/bin/perl
use strict;
use warnings;
use DBI;
use POSIX;
use Time::HiRes;
use SNMP;
use Data::Dumper;
use lib '../include';
use nms;

our $dbh = nms::db_connect();
$dbh->{AutoCommit} = 0;
$dbh->{RaiseError} = 1;

#my $qualification =  'sysname LIKE \'e71%\'';

my $qualification = <<"EOF";
(last_updated IS NULL OR now() - last_updated > poll_frequency)
AND (locked='f' OR now() - last_updated > '5 minutes'::interval)
AND ip is not null
EOF

# Borrowed from snmpfetch.pl 
our $qswitch = $dbh->prepare(<<"EOF")
SELECT 
  *,
  DATE_TRUNC('second', now() - last_updated - poll_frequency) AS overdue
FROM
  switches
  NATURAL LEFT JOIN switchtypes
WHERE
$qualification
ORDER BY
  priority DESC,
  overdue DESC
LIMIT 10
FOR UPDATE OF switches
EOF
	or die "Couldn't prepare qswitch";
our $qlock = $dbh->prepare("UPDATE switches SET locked='t', last_updated=now() WHERE switch=?")
	or die "Couldn't prepare qlock";
our $qunlock = $dbh->prepare("UPDATE switches SET locked='f', last_updated=now() WHERE switch=?")
	or die "Couldn't prepare qunlock";
my @switches = ();

our $temppoll = $dbh->prepare("INSERT INTO switch_temp (switch,temp,time) VALUES((select switch from switches where sysname = ?),?,now())")
	or die "Couldn't prepare temppoll";
sub mylog
{
	my $msg = shift;
	my $time = POSIX::ctime(time);
	$time =~ s/\n.*$//;
	printf STDERR "[%s] %s\n", $time, $msg;
}

sub populate_switches
{
	@switches = ();
	$qswitch->execute()
		or die "Couldn't get switch";
	
	while (my $ref = $qswitch->fetchrow_hashref()) {
		push @switches, {
			'sysname' => $ref->{'sysname'},
			'id' => $ref->{'switch'},
			'mgtip' => $ref->{'ip'},
			'community' => $ref->{'community'}
		};
	}
		$dbh->commit;
}

sub inner_loop
{
	mylog("Starting run");
	populate_switches();
	for my $refswitch (@switches) {
		my %switch = %{$refswitch};
		mylog( "START: Polling $switch{'sysname'} ($switch{'mgtip'}) ");

		$switch{'start'} = time;
		$qlock->execute($switch{'id'})
			or die "Couldn't lock switch";
		$dbh->commit;
		my $s = new SNMP::Session(DestHost => $switch{'mgtip'},
					  Community => $switch{'community'},
					  Version => '2');
			my @vars = ();
			push @vars, [ "sysName", 0];
			push @vars, [ "sysDescr", 0];
			push @vars, [ "1.3.6.1.4.1.2636.3.1.13.1.7.7.1.0", 0];
			my $varlist = SNMP::VarList->new(@vars);
			$s->get($varlist, [ \&ckcall, \%switch ]);
		$s->gettable('ifTable',callback => [\&callback, \%switch]);
	}
	mylog( "Added " . @switches . " ");
	SNMP::MainLoop(5);
}

sub ckcall
{
	my %switch = %{$_[0]};

	my $vars = $_[1];
	my ($sysname,$sysdescr,$temp) = (undef,undef,undef);
	for my $var (@$vars) {
		if ($var->[0] eq "sysName") {
			$sysname = $var->[2];
		} elsif ($var->[0] eq "sysDescr") {
			$sysdescr = $var->[2];
		} elsif ($var->[0] eq "enterprises.2636.3.1.13.1.7.7.1.0.0") {
			$temp = $var->[2];
		}
	}
	if (defined $temp && $temp =~ /^\d+$/) {
		$temppoll->execute($switch{'sysname'},$temp);
	} else {
		warn "Couldn't read temp for " . $switch{'sysname'} . ", got " . (defined $temp ? $temp : "undef");
	}
	$dbh->commit;
}
my @values = ('ifDescr','ifSpeed','ifType','ifOperStatus','ifInErrors','ifOutErrors','ifOutOctets','ifInOctets');
my $query = "INSERT INTO polls2 (switch,time";
foreach my $val (@values) {
	$query .= ",$val";
}
$query .= ") VALUES(?,timeofday()::timestamp";
foreach my $val (@values) {
	$query .= ",?";
}
$query .= ");";

our $qpoll = $dbh->prepare($query)
	or die "Couldn't prepare qpoll";
sub callback
{
	my %switch = %{$_[0]};
	my $table = $_[1];

	my %ifs = ();

	foreach my $key (keys %{$table}) {
		my $descr = $table->{$key}->{'ifDescr'};

		if ($descr =~ m/(ge|xt|xe)-/ && $descr !~ m/\./) {
			$ifs{$descr} = $table->{$key};
		}
	}


	foreach my $key (keys %ifs) {
		my @vals = ();
		foreach my $val (@values) {
			if (!defined($ifs{$key}{$val})) {
				die "Missing data";
			}
			push @vals, $ifs{$key}{$val};
		}
		$qpoll->execute($switch{'id'},@vals) || die "ops";
	}
	mylog( "STOP: Polling $switch{'sysname'} took " . (time - $switch{'start'}) . "s");
	$qunlock->execute($switch{'id'})
		or die "Couldn't unlock switch";
	$dbh->commit;
}

while (1) {
	inner_loop();
}

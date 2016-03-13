#!/usr/bin/perl

use strict;
use warnings;
use SNMP;
use Data::Dumper;
use DBI;
use lib '/srv/tgmanage/include';
use nms;

SNMP::initMib();
SNMP::addMibDirs("/srv/tgmanage/mibs");
SNMP::addMibDirs("/tmp/tmp.esQYrkg9MW/v2");
SNMP::loadModules('SNMPv2-MIB');
SNMP::loadModules('ENTITY-MIB');
SNMP::loadModules('IF-MIB');
SNMP::loadModules('LLDP-MIB');
SNMP::loadModules('IP-MIB');
SNMP::loadModules('IP-FORWARD-MIB');

our $row=7;
my $sess = SNMP::Session->new(DestHost => 'localhost', Community => 'public', Version => 2, UseEnums => 1);
my $dbh = nms::db_connect();
my $sth = $dbh->prepare("INSERT INTO snmp (switch,data) VALUES((select switch from switches where sysname=?), ?)");

my @getThese = [['ifTable'], ['ifXTable']];

while(1) {
	$sess->bulkwalk(0, 10, @getThese, \&callback);
	SNMP::MainLoop(10);
}


sub callback{
	my @top = $_[0];
	my %tree;
	my %nics;
	my @nicids;
	for my $ret (@top) {
		for my $var (@{$ret}) {
			for my $inner (@{$var}) {
				my ($tag,$type,$name,$iid, $val) = ( $inner->tag ,$inner->type , $inner->name, $inner->iid, $inner->val);
				if ($tag eq "ifPhysAddress") {
					next;
				}
				$tree{$iid}{$tag} = $val;
				if ($tag eq "ifIndex") {
					push @nicids, $iid;
				}
			}
		}
	}

	for my $nic (@nicids) {
		$nics{$tree{$nic}{'ifName'}} = $tree{$nic};
	}
	print "row: " . $row . "\n";
	$sth->execute("e" . $row . "-1", JSON::XS::encode_json(\%nics));
	if ($row > 50) {
		$row = 7;
	} else {
		$row += 2;
	}
}

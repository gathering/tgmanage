#!/usr/bin/perl

use strict;
use warnings;
use SNMP;
use Data::Dumper;

SNMP::initMib();
SNMP::addMibDirs("/srv/tgmanage/mibs");
#SNMP::addMibDirs("/tmp/tmp.X6Xt4LvFKn/v2");
SNMP::loadModules('SNMPv2-MIB');
SNMP::loadModules('ENTITY-MIB');
SNMP::loadModules('IF-MIB');
SNMP::loadModules('LLDP-MIB');
SNMP::loadModules('IP-MIB');
SNMP::loadModules('IP-FORWARD-MIB');

my $sess = SNMP::Session->new(DestHost => 'localhost', Community => 'public', Version => 2, UseEnums => 1);

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
	print Dumper(\%nics);
}

#!/bin/bash

set -e

source include/tgmanage.cfg.sh
if [ -z ${PRIMARY} ]
then
	echo "Not configured!";
	exit 1;
fi;

ssh -l root ${PRIMARY} "/etc/init.d/isc-dhcp-server restart"
ssh -l root ${PRIMARY} "/usr/sbin/rndc reload"
ssh -l root ${SECONDARY} "/usr/sbin/rndc reload"

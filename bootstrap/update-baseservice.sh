#!/bin/bash

set -e

BASE="";
if [ -n $1 ]
then
	BASE=$1
	echo "Using base path ${BASE}"
fi

source include/tgmanage.cfg.sh
if [ -z ${PRIMARY} ]
then
	echo "Not configured!";
	exit 1;
fi;

cd ~/tgmanage

cat netlist.txt | ssh -l root ${PRIMARY} "~/tgmanage/bootstrap/make-missing-conf.pl master ${BASE}"
ssh -l root ${PRIMARY} "~/tgmanage/bootstrap/make-bind-include.pl master ${BASE}"
ssh -l root ${PRIMARY} "~/tgmanage/bootstrap/make-dhcpd-include.pl ${BASE}"

set +e
ssh -l root ${PRIMARY} "chown bind.bind /etc/bind/dynamic/*.zone";
set -e

cat netlist.txt | ssh -l root ${SECONDARY} "~/tgmanage/bootstrap/make-missing-conf.pl slave ${BASE}"
ssh -l root ${SECONDARY} "~/tgmanage/bootstrap/make-bind-include.pl slave ${BASE}"
ssh -l root ${SECONDARY} "~/tgmanage/bootstrap/make-dhcpd-include.pl ${BASE}"

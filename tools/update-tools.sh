#!/bin/bash

set -e

source include/tgmanage.cfg.sh
if [ -z ${PRIMARY} ]
then
	echo "Not configured!";
	exit 1;
fi;

ssh -l root ${PRIMARY} "mkdir -p ~/tgmanage"
ssh -l root ${SECONDARY} "mkdir -p ~/tgmanage"

scp -r netlist.txt root@${PRIMARY}:tgmanage/
scp -r tools root@${PRIMARY}:tgmanage/
scp -r tools root@${SECONDARY}:tgmanage/
scp -r include root@${PRIMARY}:tgmanage/
scp -r include root@${SECONDARY}:tgmanage/
scp -r clients root@${PRIMARY}:tgmanage/
scp -r clients root@${SECONDARY}:tgmanage/

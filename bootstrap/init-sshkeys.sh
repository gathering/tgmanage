#!/bin/bash

set -e

source include/tgmanage.cfg.sh
if [ -z ${PRIMARY} ]
then
	echo "Not configured!";
	exit 1;
fi;

ssh-keygen -P '' -f ~/.ssh/id_rsa -b 2048
ssh-copy-id root@${PRIMARY}
ssh-copy-id root@${SECONDARY}

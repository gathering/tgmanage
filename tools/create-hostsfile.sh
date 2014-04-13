#!/bin/bash

set -e

source include/tgmanage.cfg.sh
if [ -z ${PRIMARY} ]
then
	echo "Not configured!";
	exit 1;
fi;

echo >> /etc/hosts
echo "# Bootstrap hosts entries for ${TGNAME} ">> /etc/hosts
echo "${PRI_V6}  ${PRIMARY}" >> /etc/hosts
echo "${PRI_V4}  ${PRIMARY}" >> /etc/hosts
echo "${SEC_V6}  ${SECONDARY}" >> /etc/hosts
echo "${SEC_V4}  ${SECONDARY}" >> /etc/hosts

#!/bin/sh

MIBS="SNMPv2 ENTITY IF LLDP IP IP-FORWARD"
ORIGPWD=$PWD
TMP=$(mktemp -d)
set -x
set -e
cd $TMP
wget ftp://ftp.cisco.com/pub/mibs/v2/v2.tar.gz
tar xvzf v2.tar.gz  --strip-components=2
mkdir -p mibs

for a in $MIBS; do
	cp v2/$a-MIB.my mibs/
done
mv mibs ${ORIGPWD}/
cd ${ORIGPWD}
rm -rf ${TMP}

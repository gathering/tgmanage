#!/bin/bash

set -e

BASE="/etc";
if [ "$1" != "" ]
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

tools/update-tools.sh
ssh -l root ${PRIMARY} "~/tgmanage/tools/install-dependencies.sh master"
ssh -l root ${SECONDARY} "~/tgmanage/tools/install-dependencies.sh slave"

if [ "${BASE}" == "/etc" ]; then
	ssh -l root ${PRIMARY} "cp -pR /etc/bind /etc/bind.dist"
	ssh -l root ${PRIMARY} "cp -pR /etc/dhcp /etc/dhcp.dist"

	ssh -l root ${SECONDARY} "cp -pR /etc/bind /etc/bind.dist"
	ssh -l root ${SECONDARY} "cp -pR /etc/dhcp /etc/dhcp.dist"
	
	set +e
	ssh -l root ${PRIMARY} "rm /etc/bind/named.conf"
	ssh -l root ${PRIMARY} "rm /etc/dhcp/dhcpd.conf"
		
	ssh -l root ${SECONDARY} "rm /etc/dhcp/dhcpd.conf"
	ssh -l root ${SECONDARY} "rm /etc/bind/named.conf"
	set -e
fi

ssh -l root ${PRIMARY} "mkdir -p ${BASE}/bind/conf-master/"
ssh -l root ${PRIMARY} "mkdir -p ${BASE}/bind/reverse/"
ssh -l root ${PRIMARY} "mkdir -p ${BASE}/bind/dynamic/"
ssh -l root ${PRIMARY} "mkdir -p ${BASE}/dhcp/conf.d/"

ssh -l root ${PRIMARY}   "~/tgmanage/tools/make-dhcp6-init.sh"
ssh -l root ${PRIMARY}   "~/tgmanage/tools/make-named.pl master ${BASE}"
ssh -l root ${PRIMARY}   "~/tgmanage/tools/make-dhcpd.pl ${BASE}"
ssh -l root ${PRIMARY}   "~/tgmanage/tools/make-first-zones.pl ${BASE}"
ssh -l root ${PRIMARY}   "~/tgmanage/tools/make-reverse4-files.pl master ${BASE}"

ssh -l root ${SECONDARY} "mkdir -p ${BASE}/dhcp/conf.d/"
ssh -l root ${SECONDARY} "mkdir -p ${BASE}/bind/conf-slave/"
ssh -l root ${SECONDARY} "mkdir -p ${BASE}/bind/slave/"

ssh -l root ${SECONDARY} "~/tgmanage/tools/make-dhcp6-init.sh"
ssh -l root ${SECONDARY} "insserv -r isc-dhcp-server"
ssh -l root ${SECONDARY} "~/tgmanage/tools/make-dhcpd.pl ${BASE}"
ssh -l root ${SECONDARY} "~/tgmanage/tools/make-named.pl slave ${BASE}"
ssh -l root ${SECONDARY} "~/tgmanage/tools/make-reverse4-files.pl slave ${BASE}"

set +e
ssh -l root ${PRIMARY}   "chown -R bind.bind ${BASE}/bind"
ssh -l root ${SECONDARY} "chown -R bind.bind ${BASE}/bind"
set -e

ssh -l root ${PRIMARY}   "echo THIS COPY OF TGMANAGE IS MANAGED FROM BOOTSTRAP SERVER > ~/tgmanage/NOTICE"
ssh -l root ${SECONDARY} "echo THIS COPY OF TGMANAGE IS MANAGED FROM BOOTSTRAP SERVER > ~/tgmanage/NOTICE"

# No point in _not_ running update-baseservice at this point....
tools/update-baseservice.sh ${BASE}

# Set up PXE environment. NOTE that we assume that TFTP-server is the ${SECONDARY} (changed from older behaviour)
ssh -l root ${SECONDARY} "~/tgmanage/tools/make-pxeboot.sh"

# all done.

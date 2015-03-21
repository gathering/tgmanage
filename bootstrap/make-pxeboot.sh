#!/bin/bash
#
# This tool is to be executed by make-base-requires.sh
# From tg14 we assume that TFTP server/PXE-boot server
# is the Secondary/SMTP/TFTP box.
#
# TODO: Either rewrite this to be run at/from the bootstrapper,
# and/or add support for ${BASE} redirection..

apt-get -y install tftpd-hpa
apt-get -y install nfs-kernel-server

cat << END > /etc/default/tftpd-hpa
TFTP_USERNAME="tftp"
TFTP_DIRECTORY="/var/lib/tftpboot"
TFTP_ADDRESS=":69"
TFTP_OPTIONS="--secure"
END

/etc/init.d/tftpd-hpa restart

mkdir -p /var/lib/tftpboot

cd ~/tgmanage
# NOTE, this step depends on an SCP of basic content from the bootstrap...
# This should be done by bootstrap/update-tools ...
cp -R pxe/* /var/lib/tftpboot

bootstrap/fetch-debinstall.sh /var/lib/tftpboot/debian
# bootstrap/fetch-ubuntulive.sh <- this tool does not exist xD
# NOTE! The pxe/ directory contains an 'ubuntu' menu...
# The files required to booting Ubuntu installer or live
# must be fetched manually (for now)

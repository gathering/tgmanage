#!/bin/bash
#
# This tool is to be executed by make-base-requires.sh
# From tg14 we assume that TFTP server/PXE-boot server
# is the Secondary/SMTP/TFTP box.

apt-get install tftpd-hpa
apt-get install nfs-kernel-server

cat << END > /etc/default/tftpd-hpa
TFTP_USERNAME="tftp"
TFTP_DIRECTORY="/var/lib/tftpboot"
TFTP_ADDRESS="0.0.0.0:69"
TFTP_OPTIONS="--secure"
END

/etc/init.d/tftpd-hpa restart

mkdir -p /var/lib/tftpboot
cp -R pxe/* /var/lib/tftpboot

tools/fetch-debinstall.sh /var/lib/tftpboot/debian
# tools/fetch-ubuntulive.sh <- this tool does not exist xD
# NOTE! The pxe/ directory contains an 'ubuntu' menu...
# The files required to booting Ubuntu installer or live
# must be fetched manually (for now)

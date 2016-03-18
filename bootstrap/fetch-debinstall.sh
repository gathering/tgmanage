#!/bin/bash -xe
INSTALLER_DEST=$1
DEBINSTROOT=http://ftp.no.debian.org/debian/dists

mkdir -p ${INSTALLER_DEST}/{wheezy,jessie}/{amd64,i386}
for DIST in wheezy jessie
do 
  for ARCH in i386 amd64; 
  do 
    for FILE in initrd.gz linux
    do 
      wget ${DEBINSTROOT}/${DIST}/main/installer-${ARCH}/current/images/netboot/debian-installer/${ARCH}/${FILE} \
           -O ${INSTALLER_DEST}/${DIST}/${ARCH}/${FILE}
    done
  done
done


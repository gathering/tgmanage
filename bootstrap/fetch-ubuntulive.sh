#!/bin/bash
INSTALLER_DEST=$1
UBUNTU_MIRROR=http://no.releases.ubuntu.com/
UBUNTU_VERSION=desktop
UBUNTU_DIST="14.10"
UBUNTU_ARCH="i386 amd64"
TMP_MNT="/mnt/tmp"

mkdir -p ${TMP_MNT}
for DIST in ${UBUNTU_DIST}
do 
  for ARCH in ${UBUNTU_ARCH} 
  do
    mkdir -p ${INSTALLER_DEST}/${UBUNTU_DIST}/${ARCH}
    wget ${UBUNTU_MIRROR}/${DIST}/ubuntu-${DIST}-${UBUNTU_VERSION}-${ARCH}.iso -O /tmp/ubuntu-${DIST}-${UBUNTU_VERSION}-${ARCH}.iso &&
    mount -o loop "/tmp/ubuntu-${DIST}-${UBUNTU_VERSION}-${ARCH}.iso" ${TMP_MNT}/ &&
    cp -Rv ${TMP_MNT}/* ${INSTALLER_DEST}/${DIST}/${ARCH}/ &&
    umount ${TMP_MNT}/
  done
    rmdir ${TMP_MNT}/
done

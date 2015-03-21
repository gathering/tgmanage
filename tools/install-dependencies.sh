#!/bin/bash -e

if [ "$1" != "master" -a "$1" != "slave" -a "$1" != "boot" ]; then
	echo "Run as $0 <boot|master|slave>"
	exit
fi

# OK, we know the content of $0 is OK. I prefer sane names.
ROLE=$1;

# Start by installing common packages. Remember to update
# this when a new common dependency is discovered, plx.
apt-get -y install \
	vim-nox \
	git \
	ntp \
	screen \
	tmux \
	dnsutils \
	build-essential \
	libnet-ip-perl \
	libnetaddr-ip-perl \
	libnet-telnet-cisco-perl \
	libnet-ping-external-perl \
	perl-modules \
	libdbi-perl \
	libdbd-pg-perl \
	libnet-telnet-perl 

if [ "${ROLE}" == "boot" ]; then
	# Install-tasks specific for the _bootstrab box_ here
	echo "Installing for bootstrap"
	apt-get -y install \
		bind9utils
fi

if [ "${ROLE}" == "master" ]; then
	# Install-tasks specific for the _primary_ here
	echo "Installing for primary/master"
	apt-get -y install \
		isc-dhcp-server \
		bind9utils \
		bind9
fi

if [ "${ROLE}" == "slave" ]; then
	# Install-tasks specific for the _secondary_ here
	echo "Installing for secondary/slave"
	apt-get -y install \
		isc-dhcp-server \
		bind9utils \
		bind9	
fi

echo "Dependency installation for ${ROLE} complete."

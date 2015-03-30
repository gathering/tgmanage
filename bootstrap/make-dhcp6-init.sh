#!/bin/bash

DHCP4_DEFAULT="/etc/default/isc-dhcp-server"
DHCP4_INIT="/etc/init.d/isc-dhcp-server"
DHCP6_DEFAULT="/etc/default/isc-dhcp6-server"
DHCP6_INIT="/etc/init.d/isc-dhcp6-server"

if [ -e "${DHCP4_DEFAULT}" ]; 
then
	echo "${DHCP4_DEFAULT} exists! Overwriting."
fi
if [ -e "${DHCP6_DEFAULT}" ]; 
then
	echo "${DHCP6_DEFAULT} exists! Overwriting."
fi

set -e

cat > ${DHCP4_DEFAULT}<<'_EOF'
# Defaults for isc-dhcp-server initscript
# Path to dhcpd's config file (default: /etc/dhcp/dhcpd.conf).
DHCPD_CONF=/etc/dhcp/dhcpd.conf

# Path to dhcpd's PID file (default: /var/run/dhcpd.pid).
DHCPD_PID=/var/run/dhcpd.pid

# Additional options to start dhcpd with.
#	Don't use options -cf or -pf here; use DHCPD_CONF/ DHCPD_PID instead
OPTIONS="-4"

# On what interfaces should the DHCP server (dhcpd) serve DHCP requests?
#	Separate multiple interfaces with spaces, e.g. "eth0 eth1".
INTERFACES="eth0"
_EOF

cat > ${DHCP6_DEFAULT}<<'_EOF'
# Defaults for isc-dhcp-server initscript
# Path to dhcpd's config file (default: /etc/dhcp/dhcpd.conf).
DHCPD_CONF=/etc/dhcp/dhcpd6.conf

# Path to dhcpd's PID file (default: /var/run/dhcpd.pid).
DHCPD_PID=/var/run/dhcpd6.pid

# Additional options to start dhcpd with.
#	Don't use options -cf or -pf here; use DHCPD_CONF/ DHCPD_PID instead
OPTIONS="-6"

# On what interfaces should the DHCP server (dhcpd) serve DHCP requests?
#	Separate multiple interfaces with spaces, e.g. "eth0 eth1".
INTERFACES="eth0"
_EOF

set +e

if [ -e "${DHCP4_INIT}" ]; 
then
	echo "${DHCP4_INIT} exists! Overwriting."
fi
if [ -e "${DHCP6_INIT}" ]; 
then
	echo "${DHCP6_INIT} exists! Overwriting."
fi

set -e

cat > ${DHCP4_INIT}<<'_EOF'
#!/bin/sh
#
#

### BEGIN INIT INFO
# Provides:          isc-dhcp-server
# Required-Start:    $remote_fs $network $syslog
# Required-Stop:     $remote_fs $network $syslog
# Should-Start:      $local_fs slapd $named
# Should-Stop:       $local_fs slapd
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: DHCP server
# Description:       Dynamic Host Configuration Protocol Server
### END INIT INFO

PATH=/sbin:/bin:/usr/sbin:/usr/bin

test -f /usr/sbin/dhcpd || exit 0

DHCPD_DEFAULT="${DHCPD_DEFAULT:-/etc/default/isc-dhcp-server}"

# It is not safe to start if we don't have a default configuration...
if [ ! -f "$DHCPD_DEFAULT" ]; then
	echo "$DHCPD_DEFAULT does not exist! - Aborting..."
	if [ "$DHCPD_DEFAULT" = "/etc/default/isc-dhcp-server" ]; then
		echo "Run 'dpkg-reconfigure isc-dhcp-server' to fix the problem."
	fi
	exit 0
fi

. /lib/lsb/init-functions

# Read init script configuration
[ -f "$DHCPD_DEFAULT" ] && . "$DHCPD_DEFAULT"

NAME=dhcpd
DESC="ISC DHCP server"
# fallback to default config file
DHCPD_CONF=${DHCPD_CONF:-/etc/dhcp/dhcpd.conf}
# try to read pid file name from config file, with fallback to /var/run/dhcpd.pid
if [ -z "$DHCPD_PID" ]; then
	DHCPD_PID=$(sed -n -e 's/^[ \t]*pid-file-name[ \t]*"(.*)"[ \t]*;.*$/\1/p' < "$DHCPD_CONF" 2>/dev/null | head -n 1)
fi
DHCPD_PID="${DHCPD_PID:-/var/run/dhcpd.pid}"

test_config()
{
	if ! /usr/sbin/dhcpd -t $OPTIONS -q -cf "$DHCPD_CONF" > /dev/null 2>&1; then
		echo "dhcpd self-test failed. Please fix $DHCPD_CONF."
		echo "The error was: "
		/usr/sbin/dhcpd -t $OPTIONS -cf "$DHCPD_CONF"
		exit 1
	fi
	touch /var/lib/dhcp/dhcpd.leases
}

# single arg is -v for messages, -q for none
check_status()
{
    if [ ! -r "$DHCPD_PID" ]; then
	test "$1" != -v || echo "$NAME is not running."
	return 3
    fi
    if read pid < "$DHCPD_PID" && ps -p "$pid" > /dev/null 2>&1; then
	test "$1" != -v || echo "$NAME is running."
	return 0
    else
	test "$1" != -v || echo "$NAME is not running but $DHCPD_PID exists."
	return 1
    fi
}

case "$1" in
	start)
		test_config
		log_daemon_msg "Starting $DESC" "$NAME"
		start-stop-daemon --start --quiet --pidfile "$DHCPD_PID" \
			--exec /usr/sbin/dhcpd -- \
			-q $OPTIONS -cf "$DHCPD_CONF" -pf "$DHCPD_PID" $INTERFACES
		sleep 2

		if check_status -q; then
			log_end_msg 0
		else
			log_failure_msg "check syslog for diagnostics."
			log_end_msg 1
			exit 1
		fi
		;;
	stop)
		log_daemon_msg "Stopping $DESC" "$NAME"
		start-stop-daemon --stop --quiet --pidfile "$DHCPD_PID"
		log_end_msg $?
		rm -f "$DHCPD_PID"
		;;
	restart | force-reload)
		test_config
		$0 stop
		sleep 2
		$0 start
		if [ "$?" != "0" ]; then
			exit 1
		fi
		;;
	status)
		echo -n "Status of $DESC: "
		check_status -v
		exit "$?"
		;;
	*)
		echo "Usage: $0 {start|stop|restart|force-reload|status}"
		exit 1 
esac

exit 0

_EOF

cat > ${DHCP6_INIT}<<'_EOF'
#!/bin/sh
#
#

### BEGIN INIT INFO
# Provides:          isc-dhcp6-server
# Required-Start:    $remote_fs $network $syslog
# Required-Stop:     $remote_fs $network $syslog
# Should-Start:      $local_fs slapd $named
# Should-Stop:       $local_fs slapd
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: DHCP server v6
# Description:       Dynamic Host Configuration Protocol Server v6
### END INIT INFO

PATH=/sbin:/bin:/usr/sbin:/usr/bin

test -f /usr/sbin/dhcpd || exit 0

DHCPD_DEFAULT="${DHCPD_DEFAULT:-/etc/default/isc-dhcp6-server}"

# It is not safe to start if we don't have a default configuration...
if [ ! -f "$DHCPD_DEFAULT" ]; then
	echo "$DHCPD_DEFAULT does not exist! - Aborting..."
	if [ "$DHCPD_DEFAULT" = "/etc/default/isc-dhcp6-server" ]; then
		echo "Run 'dpkg-reconfigure isc-dhcp6-server' to fix the problem."
	fi
	exit 0
fi

. /lib/lsb/init-functions

# Read init script configuration
[ -f "$DHCPD_DEFAULT" ] && . "$DHCPD_DEFAULT"

NAME=dhcpd
DESC="ISC DHCP server"
# fallback to default config file
DHCPD_CONF=${DHCPD_CONF:-/etc/dhcp/dhcpd6.conf}
# try to read pid file name from config file, with fallback to /var/run/dhcpd.pid
if [ -z "$DHCPD_PID" ]; then
	DHCPD_PID=$(sed -n -e 's/^[ \t]*pid-file-name[ \t]*"(.*)"[ \t]*;.*$/\1/p' < "$DHCPD_CONF" 2>/dev/null | head -n 1)
fi
DHCPD_PID="${DHCPD_PID:-/var/run/dhcpd6.pid}"

test_config()
{
	if ! /usr/sbin/dhcpd -t $OPTIONS -q -cf "$DHCPD_CONF" > /dev/null 2>&1; then
		echo "dhcpd self-test failed. Please fix $DHCPD_CONF."
		echo "The error was: "
		/usr/sbin/dhcpd -t $OPTIONS -cf "$DHCPD_CONF"
		exit 1
	fi
	touch /var/lib/dhcp/dhcpd.leases
}

# single arg is -v for messages, -q for none
check_status()
{
    if [ ! -r "$DHCPD_PID" ]; then
	test "$1" != -v || echo "$NAME is not running."
	return 3
    fi
    if read pid < "$DHCPD_PID" && ps -p "$pid" > /dev/null 2>&1; then
	test "$1" != -v || echo "$NAME is running."
	return 0
    else
	test "$1" != -v || echo "$NAME is not running but $DHCPD_PID exists."
	return 1
    fi
}

case "$1" in
	start)
		test_config
		log_daemon_msg "Starting $DESC" "$NAME"
		start-stop-daemon --start --quiet --pidfile "$DHCPD_PID" \
			--exec /usr/sbin/dhcpd -- \
			-q $OPTIONS -cf "$DHCPD_CONF" -pf "$DHCPD_PID" $INTERFACES
		sleep 2

		if check_status -q; then
			log_end_msg 0
		else
			log_failure_msg "check syslog for diagnostics."
			log_end_msg 1
			exit 1
		fi
		;;
	stop)
		log_daemon_msg "Stopping $DESC" "$NAME"
		start-stop-daemon --stop --quiet --pidfile "$DHCPD_PID"
		log_end_msg $?
		rm -f "$DHCPD_PID"
		;;
	restart | force-reload)
		test_config
		$0 stop
		sleep 2
		$0 start
		if [ "$?" != "0" ]; then
			exit 1
		fi
		;;
	status)
		echo -n "Status of $DESC: "
		check_status -v
		exit "$?"
		;;
	*)
		echo "Usage: $0 {start|stop|restart|force-reload|status}"
		exit 1 
esac

exit 0

_EOF


# Very Debian specific
# Hacked together at TG15
# FIXME :-D

DHCP4_SYSTEMD="/run/systemd/generator.late/isc-dhcp-server.service"
DHCP6_SYSTEMD="/run/systemd/generator.late/isc-dhcp6-server.service"

cat > ${DHCP4_SYSTEMD}<<'_EOF'
# Automatically generated by bootstrap

[Unit]
SourcePath=/etc/init.d/isc-dhcp-server
Description=LSB: DHCP server
Before=runlevel2.target runlevel3.target runlevel4.target runlevel5.target shutdown.target
After=remote-fs.target network-online.target systemd-journald-dev-log.socket local-fs.target slapd.service nss-lookup.target
Wants=network-online.target
Conflicts=shutdown.target

[Service]
Type=forking
Restart=no
TimeoutSec=5min
IgnoreSIGPIPE=no
KillMode=process
GuessMainPID=no
RemainAfterExit=yes
SysVStartPriority=3
ExecStart=/etc/init.d/isc-dhcp-server start
ExecStop=/etc/init.d/isc-dhcp-server stop

_EOF

cat > ${DHCP6_SYSTEMD}<<'_EOF'
# Automatically generated by bootstrap

[Unit]
SourcePath=/etc/init.d/isc-dhcp6-server
Description=LSB: DHCP server v6
Before=runlevel2.target runlevel3.target runlevel4.target runlevel5.target shutdown.target
After=remote-fs.target network-online.target systemd-journald-dev-log.socket local-fs.target slapd.service nss-lookup.target
Wants=network-online.target
Conflicts=shutdown.target

[Service]
Type=forking
Restart=no
TimeoutSec=5min
IgnoreSIGPIPE=no
KillMode=process
GuessMainPID=no
RemainAfterExit=yes
SysVStartPriority=3
ExecStart=/etc/init.d/isc-dhcp6-server start
ExecStop=/etc/init.d/isc-dhcp6-server stop

_EOF


set +e

chmod 755 ${DHCP4_INIT}
chmod 755 ${DHCP6_INIT}
touch /var/lib/dhcp/dhcpd.leases
touch /var/lib/dhcp/dhcpd6.leases



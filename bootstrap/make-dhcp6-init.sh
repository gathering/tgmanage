#!/bin/bash

DHCP_DEFAULT="/etc/default/isc-dhcp-server"
DHCP_INIT="/etc/init.d/isc-dhcp-server"

if [ -e "${DHCP_DEFAULT}" ]; 
then
	echo "${DHCP_DEFAULT} exists! Overwriting."
fi

set -e

cat > ${DHCP_DEFAULT}<<'_EOF'

# Defaults for dhcp initscript

# you can enable v4 and/or v6 protocols
V4_ENABLED="yes"
V6_ENABLED="yes"

# On what interfaces should the DHCP server (dhcpd) serve DHCP requests?
#       Separate multiple interfaces with spaces, e.g. "eth0 eth1".
INTERFACES_V4="eth0"
INTERFACES_V6="eth0"
_EOF

set +e

if [ -e "${DHCP_INIT}" ]; 
then
	echo "${DHCP_INIT} exists! Overwriting."
fi

set -e

cat > ${DHCP_INIT}<<'_EOF'

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

# It is not safe to start if we don't have a default configuration...
if [ ! -f /etc/default/isc-dhcp-server ]; then
        echo "/etc/default/isc-dhcp-server does not exist! - Aborting..."
        echo "Run 'dpkg-reconfigure isc-dhcp-server' to fix the problem."
        exit 0
fi

. /lib/lsb/init-functions

# Read init script configuration (so far only interfaces the daemon
# should listen on.)
[ -f /etc/default/isc-dhcp-server ] && . /etc/default/isc-dhcp-server

NAME=dhcpd
DESC="DHCPv4"
DHCPDPID=/var/run/dhcpd.pid

NAME6=dhcpd6
DESC6="DHCPv6"
DHCPDPID6=/var/run/dhcpd6.pid


# $1 -> version (-4 or -6)
# $2 -> config file (usually /etc/dhcp/dhcpd.conf or /etc/dhcp/dhcpd6.conf)
test_config()
{
        if ! /usr/sbin/dhcpd -t $1 -cf $2 -q > /dev/null 2>&1; then
                echo "dhcpd self-test failed. Please fix the config file."
                echo "The error was: "
                /usr/sbin/dhcpd -t -6 -cf $2
                exit 1
        fi
}

# $1 -> -v for messages, -q for none
# $2 -> PID file
# $3 -> NAME
check_status()
{
    if [ ! -r $2 ]; then
        test "$1" != -v || echo "$3 is not running."
        return 3
    fi
    if read pid < "$2" && ps -p "$pid" > /dev/null 2>&1; then
        test "$1" != -v || echo "$3 is running."
        return 0
    else
        test "$1" != -v || echo "$3 is not running but $2 exists."
        return 1
    fi
}


start_daemon()
{
        VERSION=$1
        CONF_FILE=$2
        PROCESS=$3
        PIDFILE=$4
        DESCRIPTION=$5

        shift 5
        INTERFACES=$*

        test_config "$VERSION" "$CONF_FILE";
        log_daemon_msg "Starting ISC $DESCRIPTION server" "$PROCESS";
        start-stop-daemon --start --quiet --pidfile $PIDFILE \
            --exec /usr/sbin/dhcpd -- $VERSION -q -cf $CONF_FILE \
            $INTERFACES
        sleep 2
        if check_status -q $PIDFILE $NAME; then
           log_end_msg 0
        else
            log_failure_msg "check syslog for diagnostics."
           log_end_msg 1
           exit 1
        fi
}

stop_daemon()
{
        # Is DHCPv6 enabled? or daemon is runing ?
        if test "$V6_ENABLED" = "yes" || check_status -q $DHCPDPID6 $NAME; then
                log_daemon_msg "Stopping ISC DHCPv6 server" "$NAME6"
                start-stop-daemon --stop --quiet --pidfile $DHCPDPID6
                log_end_msg $?
                rm -f "$DHCPDPID6"
        fi

        # Is DHCPv4 enabled or daemon is runing?
        if test "$V4_ENABLED" = "yes" || check_status -q $DHCPDPID $NAME; then
                log_daemon_msg "Stopping ISC DHCPv4 server" "$NAME"
                start-stop-daemon --stop --quiet --pidfile $DHCPDPID
                log_end_msg $?
                rm -f "$DHCPDPID"
        fi
}


case "$1" in
        start)
                # Is DHCPv6 enabled?
                case "$V6_ENABLED" in
                  yes)
                start_daemon "-6" "/etc/dhcp/dhcpd6.conf" \
                        $NAME6 $DHCPDPID6 $DESC6 $INTERFACES_V6
                ;;
                esac

                # Is DHCPv4 enabled?
                case "$V4_ENABLED" in
                  yes)
                start_daemon "-4" "/etc/dhcp/dhcpd.conf"  \
                        $NAME $DHCPDPID $DESC $INTERFACES_V4
                ;;
                esac

                ;;
        stop)
                stop_daemon
                ;;
        restart | force-reload)
               #test_config
                $0 stop
                sleep 2
                $0 start
                if [ "$?" != "0" ]; then
                        exit 1
                fi
                ;;
        status)
                echo -n "Status of $DESC: "
                check_status -v $DHCPDPID $NAME
                echo -n "Status of $DESC6: "
                check_status -v $DHCPDPID6 $NAME6

                exit "$?"
                ;;
        *)
                echo "Usage: $0 {start|stop|restart|force-reload|status}"
                exit 1
esac

exit 0

_EOF

set +e

chmod 755 ${DHCP_INIT} 


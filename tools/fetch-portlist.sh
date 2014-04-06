print_range() {
	FIRST=$1
	LAST=$2
	if [ "$1" = "$2" ]; then
		echo $FIRST
	else
		echo $FIRST-$LAST
	fi
}

walk_ports() {
	IP=$1
	COMMUNITY=$2

	FIRST_PORT=
	LAST_PORT=

	for PORT in $( snmpwalk -Os -m IF-MIB -v 2c -c $COMMUNITY $IP ifDescr 2>/dev/null | grep -E 'GigE|Ethernet' | cut -d. -f2 | cut -d" " -f1 ); do
		if ! snmpget -m IF-MIB -v 2c -c $COMMUNITY $IP ifHCInOctets.$PORT 2>/dev/null | grep -q 'No Such Instance'; then
			if [ "$LAST_PORT" ] && [ `expr $LAST_PORT + 1` = $PORT ]; then
				LAST_PORT=$PORT
			else
				if [ "$LAST_PORT" ]; then
					print_range $FIRST_PORT $LAST_PORT
				fi
				FIRST_PORT=$PORT
				LAST_PORT=$PORT
			fi
		fi
	done

	print_range $FIRST_PORT $LAST_PORT
}

COMMUNITY=$1
IP=$2
SYSNAME=$3
PORTS=$( walk_ports $IP $COMMUNITY | tr "\n" "," | sed 's/,$//' )

echo "insert into switchtypes values ('$SYSNAME','$PORTS',true);"
echo "insert into switches values (default,'$IP','$SYSNAME','$SYSNAME',null,default, default, '1 minute', '$COMMUNITY');"


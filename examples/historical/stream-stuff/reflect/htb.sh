#!/bin/bash
it () {
    iptables $@
    ip6tables $@
}

setup_htb() {
    FROM=$1
    TO=$2
    RATEMBIT=$3
    FIFOLIMIT=$(( RATEMBIT * 1048576 / 8 ))  # about one second
    echo $FROM..$TO ${RATEMBIT}Mbit fifolimit=$FIFOLIMIT >&2

    for i in $( seq $FROM $TO ); do
    	# slots need to be in hex, crazy enough
    	slot=$( printf %x $(( i + 1 )) )

    	# no burst! perfectly even sending at the given rate
    	echo class add dev eth0 parent 8000: classid 8000:$slot htb rate ${RATEMBIT}Mbit burst 0 mtu 576

    	# every class needs a child qdisc, plug in a plain fifo
    	# 8000kbit = 512 000
    	echo qdisc add dev eth0 parent 8000:$slot handle $slot: bfifo limit $FIFOLIMIT
    	#echo qdisc add dev eth0 parent 8000:$slot handle $slot: fq_codel limit 1000
    done
}

ethtool -K eth0 gso off tso off

# iptables stuff
it -t mangle -F OUTPUT
it -t mangle -A OUTPUT -p tcp -m multiport ! --sport 3013,3014,3015,3016,3017,3018,5013,5015,5016,5018 -j MARK --set-mark 65000
it -t mangle -A OUTPUT ! -p tcp -j MARK --set-mark 65000

(
  # reset tc
  echo qdisc del dev eth0 root

  # @Sesse  Rockj: https://www.google.com/search?q=6000+kbit%2Fsec+*+0.5+seconds+in+byte
  # @Sesse  ViD: også trenger du flere sett med køer, for 2mbit-strømmer burde shapes annerledes enn 5mbit-strømmer :-P
  
  # root qdisc should be htb
  echo qdisc add dev eth0 root handle 8000: htb r2q 100
  
  # all non-vlc traffic (fwmark 5) goes into the default class
  echo class add dev eth0 parent 8000: classid 8000:1 htb rate 10Gbit burst 8192 mtu 1514
  echo filter add dev eth0 parent 8000: handle 65000 pref 10 fw classid 8000:1
  
  # setup_htb 1 799 6        # Main stream hq 3mbps
  # setup_htb 800 1000 15    # Fuglecam raw 7-8mbps
  # # setup_htb 10000 11999 15  # South raw ??
  # # setup_htb 12000 13999 1   # South transcoded, 500 kbits
  # # setup_htb 14000 15999 25  # NOC Fisheye  15mbps ish
  # # setup_htb 20000 21999 2   # Flashstrøm 1mbps
  
  # setup_htb 1 4999 10       # Main stream hq 6mbps
  # setup_htb 5000 7999 5    # Main stream sd 2mbit
  # setup_htb 8000 9999 15    # Fuglecam raw 7-8mbps
  # setup_htb 10000 11999 15  # South raw ??
  # setup_htb 12000 13999 1   # South transcoded, 500 kbits
  # setup_htb 14000 15999 25  # NOC Fisheye  15mbps ish
  # setup_htb 16000 18999 2   # Flashstrøm fugleberget 1mbps
  # setup_htb 19000 21999 2   # Flashstrøm event 1mbps
  # setup_htb 22000 24999 2   # Flashstrøm south 1mbps
  # setup_htb 25000 27999 2   # Flashstrøm noc 1mbps
  setup_htb 1 4999 10       # Main stream hq 6mbps
  setup_htb 5000 5999 5    # Main stream sd 2mbit
  setup_htb 8000 9999 15    # Fuglecam raw 7-8mbps
  setup_htb 10000 11999 15  # South raw ??
  setup_htb 12000 13999 1   # South transcoded, 500 kbits
  setup_htb 14000 15999 25  # NOC Fisheye  15mbps ish
  setup_htb 16000 18999 2   # Flashstrøm fugleberget 1mbps
  setup_htb 19000 21999 2   # Flashstrøm event 1mbps
  setup_htb 22000 24999 2   # Flashstrøm south 1mbps
  setup_htb 25000 25999 2   # Flashstrøm noc 1mbps
  
  # decide between the classes by mark
  echo filter add dev eth0 parent 8000: handle 2 pref 20 flow map key mark baseclass 8000:2
) | tc -b

#!/bin/bash

while :; do
	date=$(date +"%Y-%m-%d-%H:%M:%S")
	#( lsof -n | grep vlc ; ssh root@gaffeltruck.tg12.gathering.org 'lsof -n | grep vlc' ) > /var/log/stream-count/$date
	sudo lsof -n | grep vlc > /var/log/stream-count/$date
	for PORT in 3013 3014 3015 3016 3017 3018 3019 5013 5015 5019; do
		for PROTO in IPv4 IPv6; do
			if [ "$PROTO" = "IPv4" ]; then
				GREPFOR='151\.216'
			else
				GREPFOR='2a02:ed02:'
			fi

			# 151.216.x.x / 2a02:ed02::/32 -> TG13
			cat /var/log/stream-count/$date | grep EST | egrep $GREPFOR | egrep "(151\.216\..*|2a02:ed02:.*):$PORT->" | cut -d'>' -f2 | sed 's/:[0-9]\+ (ESTABLISHED)//' | sort -u | grep -vEc -e "\[2a02:ed02:|151\.216\." | while read foo; do echo "$date $PORT $PROTO external $foo"; done | tee -a count_datacube.log
			cat /var/log/stream-count/$date | grep EST | egrep $GREPFOR | egrep "(151\.216\..*|2a02:ed02:.*):$PORT->" | cut -d'>' -f2 | sed 's/:[0-9]\+ (ESTABLISHED)//' | sort -u | grep -Ec -e "\[2a02:ed02:|151\.216\." | while read foo; do echo "$date $PORT $PROTO internal $foo"; done | tee -a count_datacube.log
		done
	done
	sleep 60
done;


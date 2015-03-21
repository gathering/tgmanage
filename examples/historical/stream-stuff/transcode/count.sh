#!/bin/bash

while :; do
	date=$(date +"%Y-%m-%d-%H:%M:%S")
	( lsof -n | grep vlc ; ssh root@gaffeltruck.tg12.gathering.org 'lsof -n | grep vlc' ) > /var/log/stream-count/$date
	for PORT in 3013 5013 3014 5014 3015; do
		for PROTO in IPv4 IPv6; do	
			# 176.110.x.x / 2a01:798:76a:125:: -> TG12
			# 176.31.230.19 / 2001:41d0:2:f700::2 -> OVH box
			cat /var/log/stream-count/$date | grep EST | egrep $PROTO | egrep "(176\.31\.230\.19|2001:41d0:2:f700::.*):$PORT->" | cut -d'>' -f2 | sed 's/:[0-9]\+ (ESTABLISHED)//' | sort -u | grep -vEc 'fisk' | while read foo; do echo "$date $PORT $PROTO foreign $foo"; done | tee -a count_datacube.log
			cat /var/log/stream-count/$date | grep EST | egrep $PROTO | egrep "(176\.110\..*|2a01:798:76a:125::.*):$PORT->" | cut -d'>' -f2 | sed 's/:[0-9]\+ (ESTABLISHED)//' | sort -u | grep -vEc -e "\[2a01:798:76a:|176\.110\." | while read foo; do echo "$date $PORT $PROTO external $foo"; done | tee -a count_datacube.log
			cat /var/log/stream-count/$date | grep EST | egrep $PROTO | egrep "(176\.110\..*|2a01:798:76a:125::.*):$PORT->" | cut -d'>' -f2 | sed 's/:[0-9]\+ (ESTABLISHED)//' | sort -u | grep -Ec -e "\[2a01:798:76a:|176\.110\." | while read foo; do echo "$date $PORT $PROTO internal $foo"; done | tee -a count_datacube.log
		done
	done
	sleep 60
done;


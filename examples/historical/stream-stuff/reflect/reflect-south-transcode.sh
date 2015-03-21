#!/bin/sh
while :; do
vlc -vvv --intf dummy -v --sout-http-mark-start 12000 --sout-http-mark-end 13999 udp://@:4017 vlc://quit --sout '#duplicate{dst=std{access=http,mux=ts,dst=[::]:3017},dst=std{access=udp,mux=ts,dst=[ff7e:a40:2a02:ed02:ffff::17]:2017}' --intf dummy --ttl 60
	sleep 1
done

#!/bin/sh
while :; do
sudo cvlc -vvv --intf dummy -v --sout-http-mark-start 10000 --sout-http-mark-end 11999 udp://@151.216.125.4:4016 vlc://quit --sout '#duplicate{dst=std{access=http,mux=ts,dst=[::]:3016},dst=std{access=udp,mux=ts,dst=[ff7e:a40:2a02:ed02:ffff::16]:2016}' --intf dummy --ttl 60
	sleep 1
done

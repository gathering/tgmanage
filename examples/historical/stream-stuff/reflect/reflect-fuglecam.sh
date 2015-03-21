#!/bin/bash
while :; do
sudo vlc -vvv --intf dummy -v --sout-http-mark-start 8000 --sout-http-mark-end 9999 udp://@:4015 vlc://quit --sout '#duplicate{dst=std{access=http,mux=ts,dst=[::]:3015},dst=std{access=udp,mux=ts,dst=[ff7e:a40:2a02:ed02:ffff::15]:2015}' --intf dummy --ttl 60
	sleep 1
done

#!/bin/bash
while :; do
sudo vlc -vvv --intf dummy -v --sout-http-mark-start 25000 --sout-http-mark-end 27999 udp://@:4018 vlc://quit --sout '#duplicate{dst=std{access=http,mux=ts,dst=[::]:3018},dst=std{access=udp,mux=ts,dst=[ff7e:a40:2a02:ed02:ffff::18]:2018}' --intf dummy --ttl 60
	sleep 1
done

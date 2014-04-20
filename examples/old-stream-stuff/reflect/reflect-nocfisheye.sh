#!/bin/sh
while :; do
sudo cvlc -vvv --intf dummy -v --sout-http-mark-start 14000 --sout-http-mark-end 15999 --network-caching 2000 rtsp://151.216.124.79/live.sdp vlc://quit --sout '#duplicate{dst=std{access=http,mux=ts,dst=[::]:3018},dst=std{access=udp,mux=ts,dst=[ff7e:a40:2a02:ed02:ffff::18]:2018}' --intf dummy --ttl 60
	sleep 1
done

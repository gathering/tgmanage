#!/bin/sh
while :; do
sudo cvlc -vvv --intf dummy -v --sout-http-mark-start 25000 --sout-http-mark-end 27999 udp://@:4019 vlc://quit --sout '#duplicate{dst="std{access=http{mime=video/x-flv},dst=[::]:5019/stream.flv}",dst="std{access=http,mux=ts,dst=[::]:3019}",dst="std{access=udp,mux=ts,dst=[ff7e:a40:2a02:ed02:ffff::19]:2019}"}' --intf dummy --ttl 60
	sleep 1
done

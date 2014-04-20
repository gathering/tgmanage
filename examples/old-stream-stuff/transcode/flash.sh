#!/bin/sh
# udp://@:5013
while :; do
vlc --intf dummy -vvv http://vivace.tg12.gathering.org:5013/stream.flv vlc://quit --network-caching 2000 --sout-mux-caching 3000 --sout "#std{access=http{mime=video/x-flv},dst=:5013/stream.flv}"
	sleep 1
done

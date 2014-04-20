#!/bin/sh
while :; do
vlc --intf dummy -v http://pannekake.samfundet.no:9094 vlc://quit --sout '#duplicate{dst=std{access=http,mux=ts,dst=:3014},dst=std{access=udp,mux=ts,dst=233.191.12.2:2014}' --intf dummy --ttl 20
        sleep 1
done

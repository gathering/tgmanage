#!/bin/sh
while :; do
sudo cvlc --intf dummy -v --sout-http-mark-start 5000 --sout-http-mark-end 7999 udp://@:4014 vlc://quit --sout '#duplicate{dst=std{access=http,mux=ts,dst=[::]:3014},dst=std{access=udp,mux=ts,dst=[ff7e:a40:2a02:ed02:ffff::14]:2014}' --intf dummy --ttl 60
        sleep 1
done

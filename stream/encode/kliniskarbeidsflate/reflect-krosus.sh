#!/bin/sh
while :; do vlc -vvv udp://@:9017 --network-caching 2000 --no-sout-audio --sout '#std{access=udp,mux=ts,dst=151.216.125.4:4016}' --intf dummy --ttl 60 vlc://quit;
        sleep 5
done

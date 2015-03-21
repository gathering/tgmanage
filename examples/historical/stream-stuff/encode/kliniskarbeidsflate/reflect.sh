#!/bin/sh
while :; do vlc -vvv rtsp://151.216.106.2:554/live1.sdp --network-caching 2000 --no-sout-audio --sout '#std{access=udp,mux=ts,dst=127.0.0.1:9017}' --intf dummy --ttl 60 vlc://quit;
        sleep 5
done

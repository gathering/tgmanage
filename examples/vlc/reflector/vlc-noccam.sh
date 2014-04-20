#!/bin/bash
while :; do
vlc -I dummy -vv --network-caching 500 rtsp://151.216.252.134/live.sdp vlc://quit --sout '#std{access=http{metacube},mux=ts,dst=:5003/noccam.ts}'
sleep 1
done


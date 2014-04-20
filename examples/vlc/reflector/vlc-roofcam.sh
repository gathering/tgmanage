#!/bin/bash
while :; do
vlc -I dummy -vv --network-caching 500 rtsp://151.216.252.104/live.sdp vlc://quit --sout '#std{access=http{metacube},mux=ts,dst=:5001/roofcam.ts}'
sleep 1
done


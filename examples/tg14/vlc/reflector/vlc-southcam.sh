#!/bin/bash
while :; do
vlc -I dummy -vv --network-caching 500 rtsp://151.216.234.23/live.sdp vlc://quit --sout '#std{access=http{metacube},mux=ts,dst=:5002/southcam.ts}'
sleep 1
done


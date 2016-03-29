#!/bin/bash
# reflecting purposes
source="rtsp://88.92.61.10/live.sdp"

while :; do
vlc -I dummy -vv --network-caching 500 $source vlc://quit --sout '#duplicate{dst=std{access=http{metacube},mux=ts,dst=:5004/southcam.ts},dst=std{access=http{metacube},mux=ffmpeg{mux=flv},dst=:5004/southcam.flv}'
sleep 1
done


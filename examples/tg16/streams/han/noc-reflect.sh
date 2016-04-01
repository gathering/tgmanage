#!/bin/bash
# reflecting purposes
source="rtsp://185.110.150.85/live.sdp"

while :; do
vlc -I dummy -vv --network-caching 500 $source vlc://quit --sout '#duplicate{dst=std{access=http{metacube},mux=ts,dst=:5005/noccam.ts},dst=std{access=http{metacube},mux=ffmpeg{mux=flv},dst=:5005/noccam.flv}'
sleep 1
done


#!/bin/bash
# reflecting purposes
name=noccam
# vlc input
#source="rtsp://151.216.234.23/live.sdp"
source="rtsp://151.216.254.59:554/live.sdp"
# vlc dst=
destination="[::1]:5003/$name.ts.metacube"

while :; do
vlc -I dummy -vv --network-caching 500 $source vlc://quit --sout "#std{access=http{metacube},mux=ts,dst=$destination}"
sleep 1
done

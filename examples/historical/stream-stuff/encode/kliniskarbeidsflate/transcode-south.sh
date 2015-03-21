#!/bin/sh
while :; do cvlc -vv udp://@:9017 \
 --sout-ts-shaping=1000 --sout-ts-use-key-frames --sout-ts-dts-delay=500 --sout-transcode-fps 0 --no-sout-transcode-audio-sync --network-caching 2000 \
 --no-sout-x264-interlaced --sout-x264-preset veryfast --sout-x264-tune film \
 --sout-transcode-threads 3 --sout-x264-keyint 25 --no-sout-audio \
 --sout '#duplicate{dst="transcode{vcodec=h264,height=720,vb=3000}:std{access=udp,mux=ts,dst=151.216.125.4:4017}",dst="std{access=udp,mux=ts,dst=151.216.125.4:4016}"}' \
 --intf dummy --ttl 20 vlc://quit;
        sleep 1
done

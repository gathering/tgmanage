#!/bin/sh

while :; do
cvlc -vv udp://@:4014 --network-caching 2000 --sout-x264-preset fast --sout-x264-tune film --sout-transcode-threads 22 --no-sout-x264-interlaced --sout-x264-keyint 50 --sout-x264-lookahead 100 \
--sout '#transcode{height=576,vcodec=h264,vb=2000,acodec=mp4a,aenc=fdkaac,ab=128}:std{access=udp,mux=ts,dst=151.216.125.4:4014}'
sleep 1
done

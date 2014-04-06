#!/bin/sh
while :; do
cvlc -vv --network-caching 5000 --sout-x264-preset fast --sout-transcode-threads 16 --sout-x264-tune film --no-sout-x264-interlaced --sout-x264-lookahead 50 --sout-x264-vbv-maxrate 800 --sout-x264-vbv-bufsize 800 --sout-x264-keyint 50 -v http://stream.tg13.gathering.org:3018 vlc://quit \
--sout '#transcode{width=768,height=768,vcodec=h264,vb=800}:std{access=udp,mux=ts,dst=151.216.125.4:4019}'
        sleep 1
done

#!/bin/sh
while :; do
cvlc -vv --network-caching 3000 --sout-x264-preset fast --sout-transcode-threads 2 --sout-x264-tune film --sout-mux-caching 2000 --sout-x264-lookahead 50 --sout-x264-vbv-maxrate 1500 --sout-x264-vbv-bufsize 1500 --sout-x264-keyint 50 -v http://cubemap.tg14.gathering.org/southcam.ts vlc://quit \
--sout '#transcode{height=480,vcodec=h264,vb=2000,acodec=fdkaac,ab=128}:std{access=http{metacube},mux=ffmpeg{mux=flv},dst=:5005/southcam.flv}'
        sleep 1
done

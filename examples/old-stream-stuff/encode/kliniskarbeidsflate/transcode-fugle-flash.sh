#!/bin/sh
while :; do
cvlc -vv --network-caching 3000 --sout-x264-preset fast --sout-transcode-threads 10 --sout-x264-tune film --no-sout-x264-interlaced --sout-x264-lookahead 50 --sout-x264-vbv-maxrate 800 --sout-x264-vbv-bufsize 800 --sout-x264-keyint 50 -v http://stream.tg13.gathering.org:3015 vlc://quit \
--sout '#transcode{height=480,fps=25,vcodec=h264,vb=800,acodec=aac,ab=128,deinterlace}:std{access=udp,mux=ffmpeg{mux=flv},dst=151.216.125.4:4020}'
        sleep 1
done


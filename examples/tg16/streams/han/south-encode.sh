#!/bin/bash
while :; do
cvlc -I dummy -vvvv \
 --sout-x264-preset medium --sout-x264-tune film --sout-transcode-threads 10 --no-sout-x264-interlaced --sout-mux-caching 5000 --network-caching 3000 \
 --sout-x264-keyint 50 --sout-x264-lookahead 100 --sout-x264-vbv-maxrate 3000 --sout-x264-vbv-bufsize 3000 --ttl 60 \
 -v rtsp://88.92.61.10/live.sdp  vlc://quit \
 --sout \
'#transcode{vcodec=h264,vb=4500,acodec=null}:duplicate{dst=std{access=http{metacube},mux=ts,dst=:5006/southcamlb.ts},dst=std{access=http{metacube},mux=ffmpeg{mux=flv},dst=:5006/southcamlb.flv}'
sleep 1
done

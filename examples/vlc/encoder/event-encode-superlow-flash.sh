#!/bin/bash
while :; do
cvlc -I dummy -vvvv \
 --sout-x264-preset fast --sout-x264-tune film --sout-transcode-threads 2 --no-sout-x264-interlaced --network-caching 3000 --sout-mux-caching 5000 \
 --sout-x264-keyint 50 --sout-x264-lookahead 100 --sout-x264-vbv-maxrate 500 --sout-x264-vbv-bufsize 500 --ttl 60 \
 -v http://cubemap.tg14.gathering.org/event.ts vlc://quit \
 --sout '#transcode{vcodec=h264,vb=500,height=360,acodec=mp4a,aenc=fdkaac,ab=64}:duplicate{dst=std{access=http{metacube},mux=ts,dst=:5006/event-superlow.ts},dst=std{access=udp,mux=ts,dst=[ff7e:a40:2a02:ed02:ffff::17]:2017},dst=std{access=http{metacube},mux=ffmpeg{mux=flv},dst=:5006/event-superlow.flv}'
sleep 1
done

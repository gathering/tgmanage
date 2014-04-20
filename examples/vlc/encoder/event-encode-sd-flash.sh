#!/bin/bash
while :; do
cvlc -I dummy -vvvv \
 --sout-x264-preset medium --sout-x264-tune film --sout-transcode-threads 6 --no-sout-x264-interlaced --network-caching 3000 --sout-mux-caching 5000 \
 --sout-x264-keyint 50 --sout-x264-lookahead 100 --sout-x264-vbv-maxrate 2000 --sout-x264-vbv-bufsize 2000 --ttl 60 \
 -v http://cubemap.tg14.gathering.org/event.ts vlc://quit \
 --sout '#transcode{vcodec=h264,vb=2000,height=480,acodec=mp4a,aenc=fdkaac,ab=256}:duplicate{dst=std{access=http{metacube},mux=ts,dst=:5006/event-sd.ts},dst=std{access=udp,mux=ts,dst=[ff7e:a40:2a02:ed02:ffff::16]:2016},dst=std{access=http{metacube},mux=ffmpeg{mux=flv},dst=:5004/event.flv},dst=std{access=http,mux=ts,dst=:5006/event-sd.ts.yes}'
sleep 1
done

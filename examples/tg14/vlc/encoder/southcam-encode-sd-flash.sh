#!/bin/bash
while :; do
cvlc -I dummy -vvvv \
 --sout-x264-preset veryfast --sout-x264-tune film --sout-transcode-threads 2 --no-sout-x264-interlaced --network-caching 3000 --sout-mux-caching 3000 \
 --sout-x264-keyint 50 --sout-x264-lookahead 100 --sout-x264-vbv-maxrate 3000 --sout-x264-vbv-bufsize 3000 --ttl 60 \
 -v http://cubemap.tg14.gathering.org/southcam.ts vlc://quit \
 --sout '#transcode{vcodec=h264,vb=2000,height=480,acodec=mp4a,aenc=fdkaac,ab=256}:duplicate{dst=std{access=http{metacube},mux=ts,dst=:5005/southcam-sd.ts},dst=std{access=udp,mux=ts,dst=[ff7e:a40:2a02:ed02:ffff::17]:2017},dst=std{access=http{metacube},mux=ffmpeg{mux=flv},dst=:5005/southcam.flv}'
sleep 1
done

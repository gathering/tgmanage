#!/bin/bash
cvlc -I dummy -vvvv --sout-x264-preset medium --sout-x264-tune film --sout-transcode-threads 5 --no-sout-x264-interlaced --sout-mux-caching 5000 \
 --sout-x264-keyint 50 --sout-x264-lookahead 100 --sout-x264-vbv-maxrate 2000 --sout-x264-vbv-bufsize 2000 --ttl 60 --live-caching 10000 --network-caching 10000 \
 -v http://cubemap.tg16.gathering.org/anakin.ts vlc://quit \
 --sout \
'#transcode{vcodec=h264,vb=2000,acodec=mp4a,ab=128,channels=2,height=576}:duplicate{dst=std{access=http{metacube},mux=ts,dst=:5009/eventsd.ts},dst=std{access=http{metacube},mux=ffmpeg{mux=flv},dst=:5009/eventsd.flv}'

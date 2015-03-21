#!/bin/bash
cvlc -I dummy -vvvv --decklink-audio-connection embedded --live-caching 3000 --decklink-aspect-ratio 16:9 --decklink-mode hp50 --decklink-video-connection sdi \
 --sout-x264-preset medium --sout-x264-tune film --sout-transcode-threads 12 --no-sout-x264-interlaced --sout-mux-caching 3000 \
 --sout-x264-keyint 50 --sout-x264-lookahead 100 --sout-x264-vbv-maxrate 6000 --sout-x264-vbv-bufsize 6000 --ttl 60 \
 -v decklink:// vlc://quit \
 --sout '#transcode{vcodec=h264,vb=6000,acodec=mp4a,aenc=fdkaac,ab=256}:duplicate{dst=std{access=http{metacube},mux=ts,dst=:5004/event.ts},dst=std{access=udp,mux=ts,dst=[ff7e:a40:2a02:ed02:ffff::15]:2015}'

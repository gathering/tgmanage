#!/bin/bash
cvlc -I dummy -vvvv --decklink-audio-connection embedded --live-caching 3000 --decklink-aspect-ratio 16:9 --decklink-video-connection sdi \
 --sout-x264-preset slow --sout-x264-tune film --sout-transcode-threads 15 --no-sout-x264-interlaced --sout-mux-caching 3000 \
 --sout-x264-keyint 50 --sout-x264-lookahead 100 --sout-x264-vbv-maxrate 4000 --sout-x264-vbv-bufsize 4000 --ttl 60 \
 -v decklink:// vlc://quit \
 --sout \
'#transcode{vcodec=h264,vb=5500,acodec=mp4a,ab=256,channels=2}:duplicate{dst=std{access=http{metacube},mux=ts,dst=:5004/anakin.ts},dst=std{access=http{metacube},mux=ffmpeg{mux=flv},dst=:5004/anakin.flv}'

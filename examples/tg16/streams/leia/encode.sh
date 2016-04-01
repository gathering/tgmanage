#!/bin/bash
cvlc -I dummy -vvvv --decklink-audio-connection embedded --live-caching 3000 --decklink-aspect-ratio 16:9 --decklink-mode hp50 --decklink-video-connection sdi \
 --sout-x264-preset medium --sout-x264-tune film --sout-transcode-threads 15 --no-sout-x264-interlaced --sout-mux-caching 3000 \
 --sout-x264-keyint 50 --sout-x264-lookahead 100 --sout-x264-vbv-maxrate 6000 --sout-x264-vbv-bufsize 6000 --ttl 60 \
 -v decklink:// vlc://quit \
 --sout \
'#transcode{vcodec=h264,vb=5500,acodec=mp4a,ab=256,channels=2}:duplicate{dst=std{access=http{metacube},mux=ts,dst=:5004/leia.ts},dst=std{access=http{metacube},mux=ffmpeg{mux=flv},dst=:5004/leia.flv}'

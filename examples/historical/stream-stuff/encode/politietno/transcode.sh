#!/bin/sh
cvlc -I dummy -vvvv --decklink-audio-connection embedded --live-caching 2000 --decklink-aspect-ratio 16:9 --decklink-mode hp50 \
 --sout-x264-preset slow --sout-x264-tune film --sout-transcode-threads 23 --no-sout-x264-interlaced \
 --sout-x264-keyint 50 --sout-x264-lookahead 100 --sout-x264-vbv-maxrate 6000 --sout-x264-vbv-bufsize 6000 \
 -v decklink:// vlc://quit \
 --sout '#transcode{vcodec=h264,vb=6000,acodec=mp4a,aenc=fdkaac,ab=256}:std{access=udp,mux=ts,dst=151.216.125.4:4013}'

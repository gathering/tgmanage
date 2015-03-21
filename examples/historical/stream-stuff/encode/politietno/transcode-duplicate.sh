#!/bin/sh
while :; do
cvlc -vv --decklink-audio-connection embedded --live-caching 2000 --decklink-aspect-ratio 16:9 --decklink-mode hp50 \
 --sout-x264-preset fast --sout-x264-tune film --sout-transcode-threads 24 --no-sout-x264-interlaced --sout-x264-keyint 50 --sout-x264-lookahead 100 --sout-x264-vbv-maxrate 4000 --sout-x264-vbv-bufsize 4000 decklink:// vlc://quit \
 --sout '#duplicate{dst="transcode{vcodec=h264,vb=6000,acodec=mp4a,aenc=fdkaac,ab=256}:std{access=udp,mux=ts,dst=151.216.125.4:4013}",dst="transcode{height=576,vcodec=h264,vb=2000,acodec=mp4a,aenc=fdkaac,ab=128}:std{access=udp,mux=ts,dst=151.216.125.4:4014}"}'
sleep 1
done

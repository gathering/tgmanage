#!/bin/sh
# event signal:
# transcode hd and move to reflector
# mirror signal to encoder2 (kliniskarbeidsflate) and transcode sd -> reflector
while :; do
cvlc -vv --decklink-audio-connection embedded --live-caching 2000 --decklink-aspect-ratio 16:9 --decklink-mode hp50 \
 --sout-x264-preset fast --sout-x264-tune film --sout-transcode-threads 22 --no-sout-x264-interlaced --sout-x264-keyint 50 --sout-x264-lookahead 100 decklink:// vlc://quit \
 --sout '#duplicate{dst="transcode{vcodec=h264,vb=6000,acodec=mp4a,aenc=fdkaac,ab=256}:std{access=udp,mux=ts,dst=151.216.125.4:4013}",dst="std{access=udp,mux=ts,dst=151.216.125.9:4014}"}'
sleep 1
done

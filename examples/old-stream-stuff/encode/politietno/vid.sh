#!/bin/sh
# VLC for box connected to broadcast-equipment Blackmagic/Decklink: Audio and Video from SDI Transcodes HD and sends via UDP to reflector - Marius / Tech:Server
while :; do cvlc -vv --no-decklink-tenbits --decklink-audio-connection embedded --live-caching 1800 --decklink-aspect-ratio 16:9 --decklink-mode hp50 \
 --sout-x264-preset medium --sout-x264-tune film --sout-transcode-threads 15 --no-sout-x264-interlaced --sout-x264-keyint 100 --sout-x264-lookahead 50 --sout-x264-vbv-maxrate 7000 --sout-x264-vbv-bufsize 7000 -v decklink:// vlc://quit \
 --sout '#transcode{vcodec=h264,vb=3000,acodec=mp3,ab=256}:std{access=udp,mux=ts,dst=151.216.125.4:4013}'
        sleep 1
done

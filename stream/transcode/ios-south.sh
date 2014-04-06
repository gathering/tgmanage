#!/bin/sh
while :; do
vlc -I dummy --live-caching 0 udp://@:5114 vlc://quit --sout='#std{access=livehttp{seglen=10,delsegs=true,numsegs=5,index=/srv/stream.tg12.gathering.org/ios/south.m3u8,index-url=http://stream.tg12.gathering.org/ios/south-########.ts},mux=ts{use-key-frames},dst=/srv/stream.tg12.gathering.org/ios/south-########.ts}' 
	sleep 2
done

# --sout-x264-level 30

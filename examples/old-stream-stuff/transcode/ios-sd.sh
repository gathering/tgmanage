#!/bin/sh
while :; do
vlc -I dummy --live-caching 0 http://vivace.tg12.gathering.org:5013/stream.flv --sout-x264-profile baseline --sout-x264-preset veryfast --sout-x264-aud --sout-x264-keyint 30 --sout-x264-ref 1 vlc://quit --sout='#std{access=livehttp{seglen=10,delsegs=true,numsegs=5,index=/srv/stream.tg12.gathering.org/ios/sd.m3u8,index-url=http://stream.tg12.gathering.org/ios/sd-########.ts},mux=ts{use-key-frames},dst=/srv/stream.tg12.gathering.org/ios/sd-########.ts}'
	sleep 2
done

# --sout-x264-level 30

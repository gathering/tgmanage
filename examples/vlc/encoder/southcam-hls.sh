#!/bin/sh
while :; do
vlc -vv -I dummy --live-caching 0 http://cubemap.tg14.gathering.org/southcam.flv vlc://quit --sout='#std{access=livehttp{seglen=10,delsegs=true,numsegs=5,index=/srv/stream.tg14.gathering.org/hls/southcam.m3u8,index-url=http://stream.tg14.gathering.org/hls/southcam-########.ts},mux=ts{use-key-frames},dst=/srv/stream.tg14.gathering.org/hls/southcam-########.ts}'
	sleep 2
done

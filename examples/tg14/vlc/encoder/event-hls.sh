#!/bin/sh
while :; do
vlc -vv -I dummy --live-caching 0 http://cubemap.tg14.gathering.org/event.flv vlc://quit --sout='#std{access=livehttp{seglen=10,delsegs=true,numsegs=5,index=/srv/stream.tg14.gathering.org/hls/event.m3u8,index-url=http://stream.tg14.gathering.org/hls/event-########.ts},mux=ts{use-key-frames},dst=/srv/stream.tg14.gathering.org/hls/event-########.ts}'
	sleep 2
done

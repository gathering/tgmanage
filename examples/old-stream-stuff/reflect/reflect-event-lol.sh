#!/bin/sh
while :; do
sudo cvlc --intf dummy -v --sout-http-mark-start 0 --sout-http-mark-end 4999 udp://@:4013 vlc://quit --sout \
'#duplicate{dst=std{access=http,mux=ts,dst=[::]:3013}",dst=std{access=udp,mux=ts,dst=[ff7e:a40:2a02:ed02:ffff::13]:2013},dst=std{access=livehttp{seglen=5,delsegs=true,numsegs=5,index=/srv/stream.tg13.gathering.org/ios/event.m3u8,index-url=http://stream.tg13.gathering.org/ios/event-########.ts},mux=ts{use-key-frames},dst=/srv/stream.tg13.gathering.org/ios/event-########.ts}}}' \
--intf dummy --ttl 60
        sleep 1
done

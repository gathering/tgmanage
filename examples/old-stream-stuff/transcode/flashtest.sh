#!/bin/sh
while :; do
	vlc --intf dummy -vvv http://stream.tg12.gathering.org:3013 vlc://quit --udp-caching 1000 --sout-x264-tune film --sout-x264-keyint 25 --sout-x264-preset veryfast --sout "#transcode{width=980,height=550,vcodec=h264,vb=1000,acodec=aac,ab=128}:std{access=http{mime=video/x-flv},dst=:5013/stream.flv}"
        sleep 1
done

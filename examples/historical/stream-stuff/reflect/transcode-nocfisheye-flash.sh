#!/bin/sh
while :; do
sudo cvlc -vv --sout-http-mark-start 25000 --sout-http-mark-end 27999 --network-caching 5000 --sout-x264-preset fast --sout-transcode-threads 10 --sout-x264-tune film --no-sout-x264-interlaced --sout-x264-lookahead 50 --sout-x264-vbv-maxrate 800 --sout-x264-vbv-bufsize 800 --sout-x264-keyint 50 -v http://stream.tg13.gathering.org:3018 vlc://quit \
--sout '#transcode{height=480,fps=25,vcodec=h264,vb=800,acodec=aac,ab=128}:std{access=http{mime=video/x-flv},dst=[::]:5018/stream.flv}'
        sleep 1
done

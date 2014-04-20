#!/bin/sh
while :; do
sudo cvlc -vv --sout-http-mark-start 16000 --sout-http-mark-end 18999 --network-caching 3000 --sout-x264-preset fast --sout-transcode-threads 10 --sout-x264-tune film --no-sout-x264-interlaced --sout-x264-lookahead 50 --sout-x264-vbv-maxrate 800 --sout-x264-vbv-bufsize 800 --sout-x264-keyint 50 -v udp://@:4020 vlc://quit \
--sout '#std{access=http{mime=video/x-flv},mux=ffmpeg{mux=flv},dst=[::]:5015/stream.flv}'
        sleep 1
done

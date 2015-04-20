#!/bin/bash
while :; do
vlc -I dummy -vvvv \
 --sout-x264-preset medium --sout-x264-tune film --sout-transcode-threads 4 --no-sout-x264-interlaced --network-caching 2800 --sout-mux-caching 2000 \
 --sout-x264-keyint 50 --sout-x264-lookahead 100 --sout-x264-vbv-maxrate 3000 --sout-x264-vbv-bufsize 3000 --ttl 60 --no-avcodec-dr \
 -v rtsp://151.216.254.59:554/live.sdp/ vlc://quit \
 --sout \
'#transcode{vcodec=h264,vb=2000,acodec=mp4a,aenc=fdkaac,ab=256,channels=2}:duplicate{dst=std{access=http{metacube},mux=ts,dst=:5004/noccam.ts.metacube},dst=std{access=http{metacube},mux=ffmpeg{mux=flv},dst=:5004/noccam.flv.metacube}'
sleep 1
done

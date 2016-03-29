#!/bin/bash
cvlc -I dummy --network-caching 5000 --live-caching 5000 -vvvv http://cubemap.tg16.gathering.org/event.ts vlc://quit \
--sout-x264-preset medium --sout-x264-tune film --sout-mux-caching 5000 --sout-transcode-threads 8 --sout-x264-vbv-maxrate 5000 --sout-x264-vbv-bufsize 5000 --sout-avformat-options '{movflags=empty_moov+frag_keyframe+default_base_moof}' --no-avcodec-dr --sout-x264-keyint 50 \
--sout \
'#transcode{vcodec=h264,vb=3500,acodec=mp4a,ab=128,channels=2}:std{mux=ffmpeg{mux=mp4},access=http{mime=video/mp4,metacube},dst=:1994/event.mp4}'

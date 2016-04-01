#!/bin/bash
cvlc -I dummy -vvvv rtsp://88.92.61.10/live.sdp vlc://quit \
--live-caching 5000 --network-caching 5000 --sout-x264-preset medium --sout-x264-tune film --sout-mux-caching 5000 --sout-transcode-threads 6 --sout-x264-vbv-maxrate 5000 --sout-x264-vbv-bufsize 5000 --sout-avformat-options '{movflags=empty_moov+frag_keyframe+default_base_moof}' --no-avcodec-dr --sout-x264-keyint 50 \
--sout \
'#transcode{vcodec=h264,vb=3500,acodec=mp4a,ab=128,channels=2}:duplicate{dst=std{access=http{mime=video/mp4,metacube},mux=ffmpeg{mux=mp4},dst=:5006/southcamlb.mp4},dst=std{access=http{metacube},mux=ts,dst=:5006/southcamlb.ts}}' \

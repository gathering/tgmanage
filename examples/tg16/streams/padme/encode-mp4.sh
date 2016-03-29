#!/bin/bash
#'#transcode{vcodec=h264,vb=5500,acodec=mp4a,ab=256,channels=2}:duplicate{dst=std{access=http{metacube},mux=ts,dst=:5004/padme.ts},dst=std{access=http{metacube},mux=ffmpeg{mux=flv},dst=:5004/padme.flv,dst=std{access=http{mime=video/mp4},mux=ffmpeg{mux=mp4},dst=:5004/stream.mp4}}'

cvlc -I dummy -vvvv --decklink-audio-connection embedded --live-caching 3000 --decklink-aspect-ratio 16:9 --decklink-mode hp50 --decklink-video-connection sdi \
-v decklink:// vlc://quit --sout \
'#transcode{vcodec=h264,vb=5500,acodec=mp4a,ab=256,channels=2}:duplicate{dst=std{access=http{mime=video/mp4,metacube},mux=ffmpeg{mux=mp4},dst=:5004/padme.mp4},dst=std{access=http{metacube},mux=ts,dst=:5004/padme.ts}}' \
--sout-x264-preset slow --live-caching 3000 --sout-x264-tune film --sout-mux-caching 8000 --sout-x264-vbv-maxrate 5000 --sout-x264-vbv-bufsize 5000 --sout-avformat-options '{movflags=empty_moov+frag_keyframe+default_base_moof,frag_interleave=5}' --no-avcodec-dr --sout-x264-keyint 50


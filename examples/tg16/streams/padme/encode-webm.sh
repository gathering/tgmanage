#!/bin/bash
cvlc -I dummy -vvvv --decklink-audio-connection embedded --live-caching 3000 --decklink-aspect-ratio 16:9 --decklink-mode hp60 --decklink-video-connection sdi \
-v decklink:// vlc://quit --sout \
'#transcode{vcodec=VP80,vb=3000,channels=2,samplerate=44100}:std{access=http{mime=video/webm},mux=webm,dst=:8080/stream.webm}' \
--sout-mux-caching 5000

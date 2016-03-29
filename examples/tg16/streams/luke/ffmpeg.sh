#!/bin/bash
ffmpeg -y -f decklink -i 'DeckLink SDI 4K@11' -v verbose \
-c:v libx264 -tune film -preset medium -x264opts keyint=50:rc-lookahead=70:vbv-maxrate=15000:vbv-bufsize=15000:bitrate=15000 \
-c:a libfdk_aac -ac 2 -b:a 192k -threads 16 -f mpegts  - | cvlc - --sout "#std{access=http{metacube},mux=ts,dst=:5004/luke.ts}" --live-caching 3000 --file-caching 3000
#"udp://185.110.148.8:1234?pkt_size=1316&buffer_size=10485760&fifo_size=10485760&ttl=60"

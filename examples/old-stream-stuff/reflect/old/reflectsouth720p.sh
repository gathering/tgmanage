#!/bin/sh
while :; do
cvlc --intf dummy -v "#transcode{vcodec=h264,width=320,height=180,acodec=aac,ab=128,vb=500}:rtp{port=4555,sdp=rtsp://151.216.106.2:4555/stream.sdp,mp4a­-latm}"
vlc --intf dummy -v http://pannekake.samfundet.no:9093 vlc://quit --sout '#std{access=http,mux=ts,dst=:5014}' --intf dummy --ttl 30
        sleep 1
done

#!/bin/bash
while :; do
ffmpeg -i http://cubemap.tg16.gathering.org/event.ts -vcodec copy -c:a libfdk_aac -ar 44100 -ac 2 -f flv rtmp://185.110.148.11/live/event;
sleep 1
done


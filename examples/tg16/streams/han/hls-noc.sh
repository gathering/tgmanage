#!/bin/bash
while :; do
ffmpeg -thread_queue_size 16 -i http://cubemap.tg16.gathering.org/noccam.ts -f lavfi -i anullsrc -vcodec copy -c:a libfdk_aac -ar 44100 -ac 2 -f flv rtmp://185.110.148.11/live/noccam;
sleep 1
done


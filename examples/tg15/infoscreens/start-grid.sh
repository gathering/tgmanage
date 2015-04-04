#!/bin/sh
# Make some grids, you need i3, xdotool, mpv and chromium installed.
# Tech:Server
export DISPLAY=:1

MAXWAIT=30

# Start the given command and wait until it's visible
safestart()
{
    "$@" &
    mypid=$!
    for i in `seq $MAXWAIT`
    do
        if xdotool search --onlyvisible --pid $mypid; then
            return 0
        fi
        sleep 1
    done
    xmessage "Error on executing: $@" &
}


safestart mpv --no-audio -vo opengl -hwdec vaapi --cache no --cache-default no --osd-msg1 "cubemap: creativia.ts" http://cubemap.tg15.gathering.org/creativia.ts
i3-msg border none
sleep 1

safestart mpv --no-audio -vo opengl -hwdec vaapi --cache no --cache-default no --osd-msg1 "cubemap: southcam.flv" http://cubemap.tg15.gathering.org/southcam.flv
i3-msg border none
sleep 1

i3-msg split v
sleep 1

safestart mpv --no-audio -vo opengl -hwdec vaapi --cache no --cache-default no --osd-msg1 "cubemap: game.ts" http://cubemap.tg15.gathering.org/game.ts
i3-msg border none
sleep 1

i3-msg focus left
i3-msg split v
safestart mpv --no-audio -vo opengl -hwdec vaapi --cache no --cache-default no --osd-msg1 "cubemap: event.ts" http://cubemap.tg15.gathering.org/event.ts
sleep 1
i3-msg border none

#i3-msg 'workspace 2:Browser;exec chromium --kiosk --incognito http://stats.tg15.gathering.org'

exit 0

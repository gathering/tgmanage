#!/bin/bash
tgyear="tg16"
reflector1="finn"
reflector2="rey"

if [ $# -eq 0 ]; then
	epoch_to=`date +%s`
	epoch_date="`date +%Y%m%d-%H%M`"
else 
	epoch_to=`date --date "$1" +%s`
	epoch_date="`date --date \"$1\" +%Y%m%d-%H%M`"
fi
let "epoch_from = epoch_to - (60 * 60 * 24)"

wget -qO"/root/tgmanage/examples/$tgyear/streams/streamstats/cubemap_${reflector1}_detailed-$epoch_date.png" "http://munin.$tgyear.gathering.org/munin-cgi/munin-cgi-graph/$tgyear.gathering.org/${reflector1}.$tgyear.gathering.org/cubemap-pinpoint=$epoch_from,$epoch_to.png?&lower_limit=&upper_limit=&size_x=1280&size_y=720"
wget -qO"/root/tgmanage/examples/$tgyear/streams/streamstats/cubemap_${reflector2}_detailed-$epoch_date.png" "http://munin.$tgyear.gathering.org/munin-cgi/munin-cgi-graph/$tgyear.gathering.org/${reflector2}.$tgyear.gathering.org/cubemap-pinpoint=$epoch_from,$epoch_to.png?&lower_limit=&upper_limit=&size_x=1280&size_y=720"


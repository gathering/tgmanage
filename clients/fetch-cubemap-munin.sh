#!/bin/bash
#cp -p "/var/cache/munin/www/tg15.gathering.org/seamus.tg15.gathering.org/cubemap-day.png" "/root/tgmanage/examples/tg15/streamstats/cubemap_seamus_-`date +%Y%m%d_%H%M`.png"
#cp -p "/var/cache/munin/www/tg15.gathering.org/maggie.tg15.gathering.org/cubemap-day.png" "/root/tgmanage/examples/tg15/streamstats/cubemap_maggie_-`date +%Y%m%d_%H%M`.png"

epoch_to=`date +%s`
let "epoch_from = epoch_to - (60 * 60 * 24)"

wget -qO"/root/tgmanage/examples/tg15/streamstats/cubemap_maggie_detailed-`date +%Y%m%d-%H%M`.png" "http://munin.tg15.gathering.org/munin-cgi/munin-cgi-graph/tg15.gathering.org/maggie.tg15.gathering.org/cubemap-pinpoint=$epoch_from,$epoch_to.png?&lower_limit=&upper_limit=&size_x=1280&size_y=720"
wget -qO"/root/tgmanage/examples/tg15/streamstats/cubemap_seamus_detailed-`date +%Y%m%d-%H%M`.png" "http://munin.tg15.gathering.org/munin-cgi/munin-cgi-graph/tg15.gathering.org/seamus.tg15.gathering.org/cubemap-pinpoint=$epoch_from,$epoch_to.png?&lower_limit=&upper_limit=&size_x=1280&size_y=720"


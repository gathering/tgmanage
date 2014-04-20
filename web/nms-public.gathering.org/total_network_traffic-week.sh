#! /bin/sh
echo "Content-Type: image/png"
echo "Refresh: 300;/total_network_traffic-week.sh" 
echo
cat /var/lib/munin/cgi-tmp/munin-cgi-graph/tg14.gathering.org/frank.tg14.gathering.org/total_network_traffic-week.png

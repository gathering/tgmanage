#!/usr/bin/env bash

DATE="$(date +%s)"
if [ -z "$1" ] || [ -z "$2" ]; then
	echo "Usage: $0 <ip> <community>"
	exit 1;
fi
./lldpdiscover.pl $1 $2 | ./draw-neighbors.pl | dot -Tpng > ${DATE}.png
echo File name: ${DATE}.png

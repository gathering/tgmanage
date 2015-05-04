#!/usr/bin/env bash

DATE="$(date +%s)"
./lldpdiscover.pl $1 $2 | ./draw-neighbors.pl | dot -Tpng > ${DATE}.png

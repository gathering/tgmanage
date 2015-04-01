#!/bin/bash

for a in $* ; do 
X=$(( $RANDOM % 500 ))
Y=$(( $RANDOM % 500 ))
X1=$(( $X + 150 ))
Y1=$(( $Y + 20 ))
echo "insert into placements select switch, box '(($X,$Y),($X1,$Y1))' from switches where sysname = '$a';"
done

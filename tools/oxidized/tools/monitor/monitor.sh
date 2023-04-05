#!/bin/bash

f="/var/log/remote-commit.log"

inotifywait -m -e modify "$f" --format "%e" | while read -r event; do
    if [ "$event" == "MODIFY" ]; then
        host=$(tail -n 1 $f | cut -d' ' -f1)
        curl -s -X GET "http://127.0.0.1:8888/node/next/${host}" > /dev/null
	echo "Fetching config from ${host}"
    fi
done

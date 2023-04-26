#!/bin/bash
echo "Reloading config..."
curl -s http://127.0.0.1:8888/reload?format=json -O /dev/null

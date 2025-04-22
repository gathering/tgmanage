#!/usr/bin/env bash

NETBOX_URL="https://netbox.tg25.tg.no/api/extras/scripts/"
API_TOKEN="4fcbbc0f5531d413470fe0aa98134da187eaaafe"
SCRIPT_PATH="create-switch/create-switch.py"


response=$(curl -s -w "\n%{http_code}" -X POST "$NETBOX_URL" \
  -H "Authorization: Token $API_TOKEN" \
  -H "Content-Type: multipart/form-data" \
  -F "script=@$SCRIPT_PATH" )

http_body=$(echo "$response" | sed '$d')
http_code=$(echo "$response" | tail -n1)

echo "$response"

# Check the response status code
if [ "$http_code" -eq 201 ]; then
  echo "Custom script uploaded successfully!"
else
  echo "Failed to upload custom script. HTTP status code: $http_code"
  echo "Response from server: $http_body"
  exit 1
fi
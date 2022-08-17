#!/bin/bash

if [ $# -eq 0 ]
  then
    echo "Expected one argument: output file"
    exit 1
fi

body=$(curl --silent --user-agent "blockscout-solc-bin" "https://api.github.com/repos/vyperlang/vyper/releases" |
	jq --raw-output '.[].assets[] | select(.name | endswith("linux")) | .name, .browser_download_url' |
	xargs --delimiter='\n' --max-args=2 ./create_entry.sh)

body=$(echo "$body" | tr -d '\n' | sed -E "s/\}\{/\},\{/g")
body='{"builds":['$body']}'

echo "$body" | jq >"$1"

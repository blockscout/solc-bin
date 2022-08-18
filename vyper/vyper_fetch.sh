#!/bin/bash

if [ "$#" -ne 2 ]; then
	echo "Expected two arguments: <path to output file> <path to create_entry.sh>"
	exit 1
fi

# 1. Remove beta versions from list.json (because later we call "to number")
# 2. Cast every version to an array of values ("0.3.6" -> [0, 3, 6]) & Get maximum of such arrays
latest_downloaded_version=$(jq --raw-output \
	'[ .builds[] | select(.version | contains("beta") | not) ] |
    max_by(.version | split (".") | map(tonumber)) | .version' "$1")

echo "Latest downloaded version: $latest_downloaded_version"

echo "Fetching new versions..."

# 1. Get only linux releases
# 2. Remove beta versions from list.json (suppose beta only happened in the past)
# 3. Cast every version to an array of values & select only such that greater than local latest
# 4. Get name and download url of the latest versions
new_versions=$(curl --silent --user-agent "blockscout-solc-bin" "https://api.github.com/repos/vyperlang/vyper/releases" |
	jq --raw-output \
		".[].assets[] |
	    select(.name | endswith(\"linux\")) |
	    select(.name | contains(\"beta\") | not) |
	    select(
	            (.name | match(\"[0-9]+.[0-9]+.[0-9]+\") | .string | split(\".\") | map(tonumber))
	                >
              (\"$latest_downloaded_version\" | split(\".\") | map(tonumber) )
            ) |
      .name, .browser_download_url")

if [ "$new_versions" == "" ]; then
	echo "No new versions found"
	exit 0
fi

echo -e "New available versions:\n$new_versions"

body_before=$(jq '.builds[]' "$1")

body=$(echo "$new_versions" | xargs --delimiter='\n' --max-args=2 "$2")

echo "$body$body_before" | jq -n '. |= [inputs] | {"builds":.}' >"$1"

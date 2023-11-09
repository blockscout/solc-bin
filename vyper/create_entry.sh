#!/bin/bash
# The sole reason to have this script in separate file is to use xargs: it doesn't work with not-external scripts

# Create element of `builds` array in `list.json`

# Example: "vyper.0.3.6+commit.4a2124d0.linux"
long_version=$1

# Example: "https://github.com/vyperlang/vyper/releases/download/v0.3.6/vyper.0.3.6%2Bcommit.4a2124d0.linux"
browser_download_url=$2

# "vyper.0.3.6+commit.4a2124d0.linux" -> "0.3.6"
# "vyper.0.1.0-beta.17+commit.0671b7b.linux" -> "0.1.0-beta.17"
version=$(echo "$long_version" | sed -E 's/^.*([0-9]+\.[0-9]+\.[0-9]+(-beta\.[0-9]+)?).*$/\1/')

# "vyper.0.3.6+commit.4a2124d0.linux" -> "commit.4a2124d0"
build=$(echo "$long_version" | sed -E 's/.*\+(.*)\.linux/\1/')

# "--no-clobber" says do not download a file if it already exists
# redirect stdout to stderr
wget --no-clobber --directory-prefix="vyper-bin/" "$browser_download_url"
test $? -eq 0 || return 1

# Using "cut", because checksum returns "<hash> <filename>"
md5="$(md5sum -b vyper-bin/"$long_version" | cut -d " " -f1)"
sha256="$(sha256sum -b vyper-bin/"$long_version" | cut -d " " -f1)"

# "0.3.10rc5+commit.42817806 -> "0.3.10-rc5+commit.42817806"
version_with_prerelease=$(echo "$1" | sed -E 's/([^-.])(rc[0-9]+)/\1-\2/')

prerelease=$(echo "$version_with_prerelease" | grep -oE 'rc[0-9]+' || echo "")

# "vyper.0.3.6+commit.4a2124d0.linux" -> "0.3.6+commit.4a2124d0"
long_version=$(echo "$version_with_prerelease" | sed -E 's/vyper\.(.*)\.linux/\1/')

# Construct the JSON output
json_output="{
  \"path\": \"$browser_download_url\",
  \"version\": \"$version\","

# Only add the prerelease field if the prerelease variable is not empty
if [[ -n $prerelease ]]; then
  json_output+=",\n  \"prerelease\": \"$prerelease\""
fi

json_output+="\n  \"build\": \"$build\",
  \"longVersion\": \"$long_version\",
  \"md5\": \"$md5\",
  \"sha256\": \"$sha256\"
}"

echo -e "$json_output"

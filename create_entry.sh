#!/bin/bash
# The sole reason to have this script in separate file is to use xargs: it doesn't work with not-external scripts

# Create element of `builds` array in `list.json`

# Example: "vyper.0.3.6+commit.4a2124d0.linux"
long_version=$1

# Example: "https://github.com/vyperlang/vyper/releases/download/v0.3.6/vyper.0.3.6%2Bcommit.4a2124d0.linux"
browser_download_url=$2

# "vyper.0.3.6+commit.4a2124d0.linux" -> "0.3.6"
version=$(echo "$long_version" | sed -E "s/^(.*)\+.*$/\1/")

# "vyper.0.3.6+commit.4a2124d0.linux" -> "commit.4a2124d0"
build=$(echo "$long_version" | sed -E "s/.*\+(.*)\.linux/\1/")

# "--no-clobber" says do not download a file if it already exists
# redirect stdout to stderr
wget --no-clobber --directory-prefix="vyper-bin/" "$browser_download_url"
test $? -eq 0 || return 1

# Using "cut", because checksum returns "<hash> <filename>"
md5="$(md5sum -b vyper-bin/$long_version | cut -d " " -f1)"
sha256="$(sha256sum -b vyper-bin/"$long_version" | cut -d " " -f1)"

# "vyper.0.3.6+commit.4a2124d0.linux" -> "0.3.6+commit.4a2124d0"
long_version=$(echo $1 | sed -E "s/vyper\.(.*)\.linux/\1/")

echo "{
  \"path\": \"$browser_download_url\",
  \"version\": \"$version\",
  \"build\": \"$build\",
  \"longVersion\": \"$long_version\",
  \"md5\": \"$md5\",
  \"sha256\": \"$sha256\"
}"

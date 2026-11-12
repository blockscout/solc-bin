#!/bin/bash
#
# Adds new Solar (https://github.com/paradigmxyz/solar) releases to the Solar compiler lists:
# `solar.linux-amd64.list.json` and `solar.macosx-arm64.list.json`.
#
# Solar publishes `.tar.gz` archives, while a list must point at plain executables. So the
# executables of every new release are extracted and, with PUBLISH=true, uploaded unmodified
# as assets of a `solar-v<version>` release of this repository. The lists point there.
#
# `longVersion` is the solc-compatible version Solar writes into contract metadata, such as
# `0.8.38+commit.e7a91fc7.solar.0.3.0`. It is taken from `solar --version`, so the script
# has to run on one of the listed platforms.
#
# Usage: solar/solar_fetch.sh [<directory with the lists>]
#
# Environment:
#   PUBLISH   "true" to create the releases with `gh` (needs GH_TOKEN). Otherwise the
#             executables are only left in WORK_DIR, laid out as the release assets would be.
#   GH_TOKEN  GitHub token. Optional without PUBLISH, where it only raises the API rate limit.
#   WORK_DIR  Where archives are downloaded and unpacked (default: solar-bin).

set -euo pipefail

UPSTREAM_REPOSITORY="paradigmxyz/solar"
REPOSITORY="${GITHUB_REPOSITORY:-blockscout/solc-bin}"
# The first release that generates bytecode from standard JSON input.
MIN_VERSION="0.3.0"
# <platform in the list name>=<release asset of Solar>
PLATFORMS=(
	"linux-amd64=solar-x86_64-unknown-linux-musl.tar.gz"
	"macosx-arm64=solar-aarch64-apple-darwin.tar.gz"
)

lists_dir="${1:-.}"
work_dir="${WORK_DIR:-solar-bin}"
publish="${PUBLISH:-false}"

case "$(uname -s)-$(uname -m)" in
Linux-x86_64) host_platform="linux-amd64" ;;
Darwin-arm64) host_platform="macosx-arm64" ;;
*)
	echo "Unsupported host $(uname -s)-$(uname -m): cannot run Solar to read its version" >&2
	exit 1
	;;
esac

list_file() {
	echo "$lists_dir/solar.$1.list.json"
}

# Whether the list of platform $1 already has Solar version $2
is_listed() {
	jq --exit-status --arg suffix ".solar.$2" \
		'any(.builds[]; .longVersion | endswith($suffix))' "$(list_file "$1")" >/dev/null
}

# Downloads asset $2 of release $1, checks it against the digest GitHub reports and extracts
# the `solar` executable into $3
fetch_executable() {
	local tag=$1 asset=$2 output=$3
	local asset_info url digest archive unpacked executable

	asset_info=$(echo "$releases" | jq --compact-output --arg tag "$tag" --arg asset "$asset" \
		'.[] | select(.tag_name == $tag) | .assets[] | select(.name == $asset)')
	if [ -z "$asset_info" ]; then
		echo "Release $tag has no $asset asset" >&2
		return 1
	fi
	url=$(echo "$asset_info" | jq --raw-output '.browser_download_url')
	digest=$(echo "$asset_info" | jq --raw-output '.digest // "" | ltrimstr("sha256:")')
	if [ -z "$digest" ]; then
		echo "Asset $asset of release $tag has no sha256 digest" >&2
		return 1
	fi

	archive="$work_dir/upstream/$tag/$asset"
	mkdir -p "$(dirname "$archive")"
	curl --fail --silent --show-error --location --output "$archive" "$url"
	if [ "$(sha256sum -b "$archive" | cut -d " " -f1)" != "$digest" ]; then
		echo "Asset $asset of release $tag does not match its digest $digest" >&2
		return 1
	fi

	unpacked="$archive.unpacked"
	rm -rf "$unpacked"
	mkdir -p "$unpacked"
	tar -xzf "$archive" -C "$unpacked"
	executable=$(find "$unpacked" -type f -name solar | head -n 1)
	if [ -z "$executable" ]; then
		echo "Asset $asset of release $tag has no solar executable" >&2
		return 1
	fi
	mkdir -p "$(dirname "$output")"
	mv "$executable" "$output"
	chmod +x "$output"
}

# Creates the `builds` entry of a list for the executable $1 with long version $2 at url $3
create_entry() {
	local executable=$1 long_version=$2 url=$3
	jq --null-input \
		--arg path "$url" \
		--arg version "${long_version%%+*}" \
		--arg build "${long_version#*+}" \
		--arg longVersion "$long_version" \
		--arg sha256 "$(sha256sum -b "$executable" | cut -d " " -f1)" \
		--arg md5 "$(md5sum -b "$executable" | cut -d " " -f1)" \
		'{path: $path, version: $version, build: $build, longVersion: $longVersion, sha256: $sha256, md5: $md5}'
}

# Uploads the files $2.. as assets of release $1 of this repository, creating it if needed
publish_release() {
	local release=$1 version=${1#solar-v}
	shift
	if ! gh release view "$release" --repo "$REPOSITORY" >/dev/null 2>&1; then
		gh release create "$release" --repo "$REPOSITORY" --title "Solar v$version" --notes \
			"Unmodified \`solar\` executables from https://github.com/$UPSTREAM_REPOSITORY/releases/tag/v$version, extracted from the release archives. Solar is licensed under MIT OR Apache-2.0; see the attached license files."
	fi
	gh release upload "$release" "$@" --repo "$REPOSITORY" --clobber
}

add_release() {
	local tag=$1 version=${1#v}
	local release="solar-v$version" release_dir="$work_dir/solar-v$version"
	local platforms=() entry platform asset executable long_version="" license

	# Take the host platform first: its executable tells the version of the release.
	for entry in "${PLATFORMS[@]}"; do
		platform=${entry%%=*}
		is_listed "$platform" "$version" && continue
		if [ "$platform" = "$host_platform" ]; then
			platforms=("$entry" ${platforms[@]+"${platforms[@]}"})
		else
			platforms+=("$entry")
		fi
	done
	[ ${#platforms[@]} -eq 0 ] && return 0
	echo "Adding Solar $tag"

	fetch_executable "$tag" "$(host_asset)" "$release_dir/solar-$host_platform"
	# Solar gets no environment: it is a downloaded executable, and tokens are none of its business.
	long_version=$(env -i "$release_dir/solar-$host_platform" --version |
		sed -n 's/^Solc-Compatible Version: //p')
	if ! [[ "$long_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+\+commit\.[0-9a-f]{8}\.solar\.${version//./\\.}$ ]]; then
		echo "Unexpected solc-compatible version of Solar $tag: '$long_version'" >&2
		return 1
	fi

	local files=()
	for entry in "${platforms[@]}"; do
		platform=${entry%%=*}
		asset=${entry#*=}
		executable="$release_dir/solar-$platform"
		[ "$platform" = "$host_platform" ] || fetch_executable "$tag" "$asset" "$executable"
		# An executable for another platform cannot be run here, but it holds the same string.
		if ! grep --binary-files=text --fixed-strings --quiet "$long_version" "$executable"; then
			echo "$asset of release $tag is not version $long_version" >&2
			return 1
		fi
		files+=("$executable")
	done

	if [ "$publish" = "true" ]; then
		for license in LICENSE-MIT LICENSE-APACHE; do
			curl --fail --silent --show-error --location --output "$release_dir/$license" \
				"https://raw.githubusercontent.com/$UPSTREAM_REPOSITORY/$tag/$license"
			files+=("$release_dir/$license")
		done
		publish_release "$release" "${files[@]}"
	fi

	# The lists are updated last, so that they never point at assets that are not there.
	for entry in "${platforms[@]}"; do
		platform=${entry%%=*}
		executable="$release_dir/solar-$platform"
		create_entry "$executable" "$long_version" \
			"https://github.com/$REPOSITORY/releases/download/$release/solar-$platform" >"$executable.json"
		jq --slurpfile entry "$executable.json" '.builds = $entry + .builds' \
			"$(list_file "$platform")" >"$executable.list.json"
		mv "$executable.list.json" "$(list_file "$platform")"
		rm "$executable.json"
		echo "Added $long_version to $(list_file "$platform")"
	done
}

host_asset() {
	local entry
	for entry in "${PLATFORMS[@]}"; do
		[ "${entry%%=*}" = "$host_platform" ] && echo "${entry#*=}"
	done
}

for entry in "${PLATFORMS[@]}"; do
	[ -f "$(list_file "${entry%%=*}")" ] || echo '{"builds": []}' | jq . >"$(list_file "${entry%%=*}")"
done

echo "Fetching Solar releases..."
auth_header=()
[ -n "${GH_TOKEN:-}" ] && auth_header=(--header "Authorization: Bearer $GH_TOKEN")
releases=$(curl --fail --silent --show-error --user-agent "blockscout-solc-bin" \
	--header "Accept: application/vnd.github+json" ${auth_header[@]+"${auth_header[@]}"} \
	"https://api.github.com/repos/$UPSTREAM_REPOSITORY/releases?per_page=100")

# Full releases only, oldest first: new entries are put at the top of a list.
tags=$(echo "$releases" |
	jq --raw-output '.[] | select((.draft or .prerelease) | not) | .tag_name' |
	grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V)

failed=0
for tag in $tags; do
	# `sort -V` puts the smaller version first
	if [ "$(printf '%s\n%s\n' "$MIN_VERSION" "${tag#v}" | sort -V | head -n 1)" != "$MIN_VERSION" ]; then
		continue
	fi
	# A release that cannot be added is tried again on the next run.
	add_release "$tag" || {
		echo "Failed to add Solar $tag" >&2
		failed=1
	}
done

exit $failed

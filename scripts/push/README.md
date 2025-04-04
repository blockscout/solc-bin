# Push script

Script for manual launch github actions for building solc

## What does it do

1. This script will read `version_list.txt`
1. For every version in this file
   1. it replaces `{{ .Version }}` in `./build.yml` with version name
   1. it creates commit with create/update `.github/workflows/build.yml` file
   1. it pushes this commit to current branch of origin

## How to run

1. Install [go](https://go.dev/doc/install)
1. Put versions you want to update in `versions_list.txt`
1. Create new branch
1. Run

```bash
go run ./scripts/push
```

1. In case of error, try to run `go mod tidy`

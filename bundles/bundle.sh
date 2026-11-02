#!/usr/bin/env sh

set -e

help() {
  echo "Bundles the content of 'latest' into a 'v<version>-core-r<revision>.tar.gz' file in 'out'"
  echo "Usage: $0 <version> <revision>"
  echo "Example: $0 0.4.2 0"
}

if [ $# -lt 2 ]; then
  help
  exit 1
fi

VERSION=$1
REV=$2

mkdir -p out

tar czf "out/v$VERSION-core-r$REV.tar.gz" --transform "s|^latest|v$VERSION-core-r$REV|" latest

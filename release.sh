#!/bin/bash
# Publishes a new MXMenu version.
#   ./release.sh 0.2.0
# Tags the current commit and pushes the tag; GitHub Actions builds the app and
# creates the release with MXMenu.zip. Installed copies update on their next check.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:?Usage: ./release.sh <version>, e.g. ./release.sh 0.2.0}"
VERSION="${VERSION#v}"

if [ -n "$(git status --porcelain)" ]; then
  echo "Commit or stash your changes first." >&2
  exit 1
fi

git tag "v$VERSION"
git push origin HEAD "v$VERSION"

echo "Tagged v$VERSION. The release appears once the Build workflow finishes."

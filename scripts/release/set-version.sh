#!/bin/bash
# Writes a version into the one place that holds it.
#
# `project.yml` is the source of truth: the Xcode project is generated from it
# and `build-dmg.sh` reads it, so nothing else needs editing.
#
# Usage: set-version.sh 0.3.0
set -euo pipefail

cd "$(dirname "$0")/../.."

version="${1:?usage: set-version.sh <version>}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Not a semantic version: $version" >&2; exit 1; }

/usr/bin/sed -i '' \
    -e "s/MARKETING_VERSION: \".*\"/MARKETING_VERSION: \"$version\"/" \
    -e "s/CURRENT_PROJECT_VERSION: \".*\"/CURRENT_PROJECT_VERSION: \"$version\"/" \
    project.yml

grep -E 'MARKETING_VERSION|CURRENT_PROJECT_VERSION' project.yml

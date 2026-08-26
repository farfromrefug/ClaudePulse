#!/bin/bash
# Works out what the next release should be called.
#
# The released versions are the `v*` tags; `project.yml` only says what the
# working tree currently builds as, which is the last release until a bump
# lands. Prints `key=value` lines, so a workflow can read it with
# `>> "$GITHUB_OUTPUT"` and a person can read it as it is.
#
# Usage: version.sh [auto|patch|minor|major]
set -euo pipefail

cd "$(dirname "$0")/../.."

requested="${1:-auto}"

# The newest release tag, falling back to what the project builds as when the
# repository has no tags yet.
current="$(git tag --list 'v*' --sort=-v:refname | head -n1 | sed 's/^v//')"
if [ -z "$current" ]; then
    current="$(awk -F'"' '/MARKETING_VERSION/ { print $2; exit }' project.yml)"
fi
: "${current:=0.0.0}"

IFS='.' read -r major minor patch <<< "$current"
: "${major:=0}" "${minor:=0}" "${patch:=0}"

# Everything since that release is what the next version has to account for.
if git rev-parse -q --verify "refs/tags/v$current" >/dev/null 2>&1; then
    range="v$current..HEAD"
else
    range="HEAD"
fi
subjects="$(git log --no-merges --pretty=format:'%s' $range || true)"
bodies="$(git log --no-merges --pretty=format:'%b' $range || true)"

# Conventional commits: a `!` marker or a BREAKING CHANGE trailer breaks the
# API, a `feat` adds to it, anything else is a fix or housekeeping. The trailer
# has to start its own line — a commit message that merely mentions the words
# is describing them, not declaring one.
suggested="patch"
if grep -qE '^[a-z]+(\([^)]*\))?!:' <<< "$subjects" || grep -qE '^BREAKING[ -]CHANGE:' <<< "$bodies"; then
    suggested="major"
elif grep -qE '^feat(\([^)]*\))?:' <<< "$subjects"; then
    suggested="minor"
fi

bump_to() {
    case "$1" in
        major) echo "$((major + 1)).0.0" ;;
        minor) echo "$major.$((minor + 1)).0" ;;
        *)     echo "$major.$minor.$((patch + 1))" ;;
    esac
}

chosen="$requested"
[ "$chosen" = "auto" ] && chosen="$suggested"

case "$chosen" in
    patch|minor|major) ;;
    *) echo "Unknown bump '$requested' — use auto, patch, minor or major." >&2; exit 1 ;;
esac

commits="$(grep -c '' <<< "$subjects" || true)"
[ -z "$subjects" ] && commits=0

cat <<EOF
current=$current
requested=$requested
suggested=$suggested
bump=$chosen
patch=$(bump_to patch)
minor=$(bump_to minor)
major=$(bump_to major)
next=$(bump_to "$chosen")
commits=$commits
range=$range
EOF

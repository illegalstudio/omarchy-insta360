#!/usr/bin/env bash
# Create and publish a semantic version release.
#
# Usage: scripts/release.sh
#   or:  make release
#
# Reads the latest v* tag, proposes the next patch version, accepts a custom
# semantic version, updates manifest.json, runs the checks, creates an
# annotated tag, and atomically pushes the branch and tag to origin.

set -euo pipefail

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: required command not found: $1" >&2
    exit 1
  fi
}

require_command git
require_command make
require_command python3

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "error: not inside a git repository" >&2
  exit 1
fi

cd "$(git rev-parse --show-toplevel)"

if [[ -n "$(git status --porcelain --untracked-files=all)" ]]; then
  echo "error: working tree is not clean; commit or stash changes first" >&2
  git status --short
  exit 1
fi

if ! git remote get-url origin >/dev/null 2>&1; then
  echo "error: git remote 'origin' is not configured" >&2
  exit 1
fi

branch="$(git symbolic-ref --quiet --short HEAD || true)"
if [[ -z "$branch" ]]; then
  echo "error: releases cannot be created from a detached HEAD" >&2
  exit 1
fi

upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
if [[ -z "$upstream" ]]; then
  echo "error: branch '$branch' has no upstream" >&2
  exit 1
fi

if [[ "$upstream" != origin/* ]]; then
  echo "error: branch '$branch' must track an origin branch" >&2
  exit 1
fi

remote_branch="${upstream#origin/}"
local_commit="$(git rev-parse HEAD)"
remote_commit="$(git ls-remote --heads origin "refs/heads/${remote_branch}" | awk 'NR == 1 { print $1 }')"
if [[ -z "$remote_commit" ]]; then
  echo "error: remote branch 'origin/$remote_branch' was not found" >&2
  exit 1
fi

if [[ "$local_commit" != "$remote_commit" ]]; then
  echo "error: branch '$branch' must match '$upstream' before releasing" >&2
  echo "  local:  $local_commit" >&2
  echo "  remote: $remote_commit" >&2
  exit 1
fi

manifest_version="$(python3 - <<'PY'
import json
from pathlib import Path

manifest = json.loads(Path("manifest.json").read_text(encoding="utf-8"))
print(manifest.get("version", ""))
PY
)"

if [[ ! "$manifest_version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  echo "error: manifest version must look like 1.2.3 (got '$manifest_version')" >&2
  exit 1
fi

latest=""
while IFS= read -r candidate; do
  if [[ "$candidate" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    latest="$candidate"
    break
  fi
done < <(
  {
    git tag --list 'v*'
    git ls-remote --tags --refs origin 'refs/tags/v*' \
      | awk '{ sub("refs/tags/", "", $2); print $2 }'
  } | sort -uVr
)

if [[ -z "$latest" ]]; then
  proposed="v${manifest_version}"
  echo "No existing semantic version tags found."
else
  if [[ ! "$latest" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "error: cannot parse latest tag '$latest'" >&2
    exit 1
  fi
  latest_major="${BASH_REMATCH[1]}"
  latest_minor="${BASH_REMATCH[2]}"
  latest_patch="${BASH_REMATCH[3]}"
  proposed="v${latest_major}.${latest_minor}.$((latest_patch + 1))"
  echo "Latest tag: $latest"
fi

echo "Manifest version: $manifest_version"
echo "Proposed next tag: $proposed"
echo
printf "Version to release [%s]: " "$proposed"
read -r input

version="${input:-$proposed}"
if [[ "$version" != v* ]]; then
  version="v${version}"
fi

if [[ ! "$version" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  echo "error: version must look like v1.2.3 (got '$version')" >&2
  exit 1
fi

target_major="${BASH_REMATCH[1]}"
target_minor="${BASH_REMATCH[2]}"
target_patch="${BASH_REMATCH[3]}"

if [[ -n "$latest" ]]; then
  if (( target_major < latest_major \
        || (target_major == latest_major && target_minor < latest_minor) \
        || (target_major == latest_major && target_minor == latest_minor \
            && target_patch <= latest_patch) )); then
    echo "error: version '$version' must be newer than '$latest'" >&2
    exit 1
  fi
fi

if git rev-parse -q --verify "refs/tags/${version}" >/dev/null; then
  echo "error: tag '$version' already exists" >&2
  exit 1
fi

if git ls-remote --exit-code --tags origin "refs/tags/${version}" >/dev/null 2>&1; then
  echo "error: tag '$version' already exists on origin" >&2
  exit 1
fi

release_version="${version#v}"
short_commit="$(git rev-parse --short HEAD)"

echo
echo "Release plan:"
echo "  version:  $release_version"
echo "  tag:      $version"
echo "  branch:   $branch"
echo "  commit:   $short_commit"
echo "  remote:   origin"
echo "  release:  GitHub Actions with generated notes"
echo
printf "Proceed? [y/N] "
read -r confirm
case "$confirm" in
  y|Y|yes|YES) ;;
  *)
    echo "Aborted."
    exit 1
    ;;
esac

python3 - "$release_version" <<'PY'
import json
from pathlib import Path
import sys

version = sys.argv[1]
path = Path("manifest.json")
manifest = json.loads(path.read_text(encoding="utf-8"))
manifest["version"] = version
path.write_text(
    json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
PY

make check

changes="$(git status --porcelain --untracked-files=all)"
if [[ -n "$changes" && "$changes" != " M manifest.json" ]]; then
  echo "error: checks produced unexpected working tree changes" >&2
  git status --short
  exit 1
fi

if git diff --quiet -- manifest.json; then
  echo "Manifest already contains version $release_version."
else
  git add manifest.json
  git commit -m "release: $version"
fi

git tag -a "$version" -m "Release $version"
git push --atomic origin "$branch" "$version"

echo
echo "Release tag $version was published."
echo "GitHub Actions is validating the tag and creating the GitHub Release."

#!/bin/bash
#
# Update mixin dependencies for a given kube-prometheus version.
# Defaults to the version set in lib/default_vars.libsonnet.
#
# Must be run from the root of the KubeAid repo.
#
# Usage:
#   ./build/kube-prometheus/update-mixin.sh <mixin-name> [version-tag]
#   ./build/kube-prometheus/update-mixin.sh --all [version-tag]
#   ./build/kube-prometheus/update-mixin.sh --list [version-tag]

set -euo pipefail

BASEDIR="$(cd "$(dirname "$0")" && pwd)"

function usage() {
  cat <<EOF
Usage: $0 <mixin-name> [version-tag]
       $0 --all [version-tag]
       $0 --list [version-tag]

Update mixin dependencies to their latest upstream version.

Arguments:
  <mixin-name>    Name of the mixin to update (see --list)
  --all           Update all direct dependencies
  [version-tag]   Target version directory (default: from default_vars)
  --list          List available mixin names
EOF
}

function find_default_version() {
  jsonnet -S -e "(import '${BASEDIR}/lib/default_vars.libsonnet').kube_prometheus_version"
}

# List direct dep names from jsonnetfile.json
function list_direct_deps() {
  jsonnet -J "$1" -S -e '
    local jf = import "jsonnetfile.json";
    local name(d) =
      if d.source.git.subdir != "" then
        local p = std.split(d.source.git.subdir, "/"); p[std.length(p) - 1]
      else
        std.rstripChars(std.split(d.source.git.remote, "/")
          [std.length(std.split(d.source.git.remote, "/")) - 1], ".git");
    std.join("\n", [name(d) for d in jf.dependencies])
  '
}

# --- parse arguments ---

if [[ $# -lt 1 ]]; then usage; exit 1; fi
case "$1" in -h|--help) usage; exit 0;; esac

VERSION="${2:-$(find_default_version)}"
INSTALLPATH="${BASEDIR}/libraries/${VERSION}"

if [[ ! -d "$INSTALLPATH" ]]; then
  echo "Version $VERSION not found at $INSTALLPATH"
  echo "Run: ./build/kube-prometheus/setup-version.sh $VERSION"
  exit 1
fi

NAMES=$(list_direct_deps "$INSTALLPATH")

if [[ "$1" == "--list" ]]; then
  echo "Available mixins for ${VERSION}:"
  echo ""
  echo "$NAMES" | sort
  exit 0
fi

if ! command -v jb &>/dev/null; then
  echo "'jb' command not found. Please install jsonnet-bundler."
  exit 1
fi

cd "$INSTALLPATH" || exit 1

function update_one() {
  local name="$1"
  local uri
  uri=$(readlink "${INSTALLPATH}/vendor/${name}")
  if [[ -z "$uri" ]]; then
    echo "Cannot resolve vendor symlink for $name"
    return 1
  fi
  echo "Updating $name..."
  jb update "$uri"
}

if [[ "$1" == "--all" ]]; then
  echo "Updating all direct dependencies in $VERSION..."
  echo ""
  while IFS= read -r name; do
    update_one "$name"
  done <<< "$NAMES"
  echo ""
  echo "Done."
  exit 0
fi

MIXIN_NAME="$1"

# Check the name is a direct dependency
if ! echo "$NAMES" | grep -qx "$MIXIN_NAME"; then
  echo "Unknown mixin: $MIXIN_NAME"
  echo ""
  echo "Available:"
  echo "$NAMES" | sort
  exit 1
fi

update_one "$MIXIN_NAME"

echo ""
echo "Done."

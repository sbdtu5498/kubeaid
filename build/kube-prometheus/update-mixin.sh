#!/bin/bash
#
# Update a single mixin dependency for a given kube-prometheus version.
# Defaults to the latest version. Re-pins jsonnetfile.json to exact commits.
#
# Must be run from the root of the KubeAid repo.
#
# Usage:
#   ./build/kube-prometheus/update-mixin.sh <mixin-name> [version-tag]
#   ./build/kube-prometheus/update-mixin.sh --list [version-tag]

set -euo pipefail

BUILDPATH=build/kube-prometheus
if [ ! -e "$BUILDPATH" ]; then
  echo "Cannot find $BUILDPATH — this script must be run from the root of the KubeAid repo."
  exit 1
fi

function usage() {
  cat <<EOF
Usage: $0 <mixin-name> [version-tag]
       $0 --list [version-tag]

Update a single mixin dependency and re-pin to the resolved commit.

Arguments:
  <mixin-name>    Name of the mixin to update (see --list)
  [version-tag]   Target version directory (default: latest)
  --list          List available mixin names from jsonnetfile.json
EOF
}

function find_latest_version() {
  jsonnet -S -e "(import '${BUILDPATH}/lib/default_vars.libsonnet').kube_prometheus_version"
}

# Read jsonnetfile.json and produce "name|uri" lines.
# Name = last path segment of the full URI (remote sans .git + subdir).
function load_mixins() {
  local installpath="$1"
  jsonnet -J "${installpath}" -S -e '
    local jf = import "jsonnetfile.json";
    local lf = import "jsonnetfile.lock.json";
    std.join("\n", [
      local remote = std.rstripChars(d.source.git.remote, ".git");
      local remote_clean = std.lstripChars(remote, "htps:/");
      local uri = if d.source.git.subdir != "" then remote_clean + "/" + d.source.git.subdir else remote_clean;
      local parts = std.split(uri, "/");
      local name = parts[std.length(parts) - 1];
      local locks = std.filter(
        function(l) l.source.git.remote == d.source.git.remote && l.source.git.subdir == d.source.git.subdir,
        lf.dependencies,
      );
      local commit = if std.length(locks) > 0 then locks[0].version else d.version;
      name + "|" + uri + "|" + commit
      for d in jf.dependencies
    ])
  '
}

function list_mixins() {
  local installpath="$1"
  local ver
  ver=$(basename "$installpath")
  echo "Available mixins for ${ver}:"
  echo ""
  load_mixins "$installpath" | sort | while IFS='|' read -r name uri commit; do
    printf "  %-20s %s (%s)\n" "$name" "$uri" "${commit:0:12}"
  done
}

# Find a mixin by name — matches last path segment of the URI.
# Returns the full URI or empty string.
function resolve_mixin() {
  local installpath="$1"
  local search="$2"
  local match=""
  local count=0

  while IFS='|' read -r name uri _commit; do
    if [[ "$name" == "$search" ]]; then
      match="$uri"
      count=$((count + 1))
    fi
  done < <(load_mixins "$installpath")

  if [[ $count -eq 1 ]]; then
    echo "$match"
  elif [[ $count -gt 1 ]]; then
    echo "Ambiguous mixin name: $search (matched $count entries)" >&2
    echo "Use --list to see all available names." >&2
    exit 1
  fi
}


function get_pinned_commit() {
  local search="$1"
  load_mixins "$INSTALLPATH" | grep "^${search}|" | head -1 | cut -d'|' -f3
}

# Parse arguments
if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

case "$1" in
  --list)
    VERSION="${2:-$(find_latest_version)}"
    INSTALLPATH="${BUILDPATH}/libraries/${VERSION}"
    if [[ ! -d "$INSTALLPATH" ]]; then
      echo "Version $VERSION not found at $INSTALLPATH"
      exit 1
    fi
    list_mixins "$INSTALLPATH"
    exit 0
    ;;
  -h|--help)
    usage
    exit 0
    ;;
esac

MIXIN_NAME="$1"
VERSION="${2:-$(find_latest_version)}"
INSTALLPATH="${BUILDPATH}/libraries/${VERSION}"

if [[ ! -d "$INSTALLPATH" ]]; then
  echo "Version $VERSION not found at $INSTALLPATH"
  echo "Run setup-version.sh first: ./build/kube-prometheus/setup-version.sh $VERSION"
  exit 1
fi

if ! command -v jb &>/dev/null; then
  echo "'jb' command not found. Please install jsonnet-bundler."
  exit 1
fi

MIXIN_URI=$(resolve_mixin "$INSTALLPATH" "$MIXIN_NAME")
if [[ -z "$MIXIN_URI" ]]; then
  echo "Unknown mixin: $MIXIN_NAME"
  echo ""
  list_mixins "$INSTALLPATH"
  exit 1
fi

cd "$INSTALLPATH" || exit 1

old_commit=$(get_pinned_commit "$MIXIN_NAME")

echo "Updating $MIXIN_NAME in $VERSION..."
jb update "$MIXIN_URI"

new_commit=$(get_pinned_commit "$MIXIN_NAME")

echo ""
if [[ "$old_commit" == "$new_commit" ]]; then
  echo "$MIXIN_NAME ($VERSION): already up to date at ${old_commit:0:12}"
else
  echo "$MIXIN_NAME ($VERSION): ${old_commit:0:12} → ${new_commit:0:12}"
fi

#!/usr/bin/env bash
# Lints common-template.jsonnet for unguarded vars field accesses.
#
# Every field accessed as vars.field or vars['field'] must be either:
#   (a) defined in default_vars (so it always has a value), OR
#   (b) guarded at the access site with std.get / std.objectHas
#
# Run from build/kube-prometheus/:
#   bash tests/lint_vars_access.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="${TEMPLATE:-${SCRIPT_DIR}/../common-template.jsonnet}"

fail=0

# ── 1. collect all field names accessed via vars.field or vars['field'] ──────

accessed=$(grep -oP "(?<![a-zA-Z_])vars\.\K[a-zA-Z_][a-zA-Z0-9_-]*|(?<![a-zA-Z_])vars\['\K[a-zA-Z0-9_-]+" "$TEMPLATE" | sort -u)

# ── 2. collect fields defined in default_vars ─────────────────────────────────
# Get all field names that have a default — jsonnet evaluates the file and jq lists the keys
defaults=$(jsonnet "${SCRIPT_DIR}/../lib/default_vars.libsonnet" | jq -r 'keys[]')

# ── 3. collect fields that are guarded at the access site ─────────────────────
# A field is "guarded" if it appears in a std.get or std.objectHas call on vars
guarded=$(grep -oP "std\.get\(vars,\s*'\K[a-zA-Z0-9_-]+|std\.objectHas\(vars,\s*'\K[a-zA-Z0-9_-]+" "$TEMPLATE" | sort -u)

# ── 4. fields checked in validate.libsonnet ────────────────────────────────────
# These may be accessed directly (no std.get/default) because validate.libsonnet
# aborts with a clear error before they're ever reached.
# Derived automatically from validate.libsonnet — do NOT hardcode here.
VALIDATE_LIB="${SCRIPT_DIR}/../lib/validate.libsonnet"
validator_required=()
while IFS= read -r field; do
  validator_required+=("$field")
done < <(grep -oP "vars,\s*'\K[a-zA-Z0-9_-]+" "$VALIDATE_LIB" | sort -u)

# ── 5. report any accessed field that is neither defaulted nor guarded ─────────

while IFS= read -r field; do
  in_defaults=$(echo "$defaults"  | grep -Fx "$field" || true)
  in_guarded=$(echo "$guarded"    | grep -Fx "$field" || true)
  in_validator=$(printf '%s\n' "${validator_required[@]}" | grep -Fx "$field" || true)

  if [[ -z "$in_defaults" && -z "$in_guarded" && -z "$in_validator" ]]; then
    echo "ERROR: unguarded vars field '$field' in $(basename "$TEMPLATE")"
    echo "       Fix: add to ${CLUSTER_VARS_FILE:-your cluster values jsonnet file}:"
    echo "         '$field': <value>,"
    fail=1
  fi
done <<< "$accessed"

exit $fail

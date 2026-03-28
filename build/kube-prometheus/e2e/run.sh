#!/usr/bin/env bash
# End-to-end compilation test for common-template.jsonnet.
# Runs build.sh against every var file in e2e/vars/<version>/ and reports pass/fail.
#
# Usage (from repo root or from build/kube-prometheus/):
#   bash build/kube-prometheus/e2e/run.sh
#   bash e2e/run.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBE_PROM_DIR="$(dirname "${SCRIPT_DIR}")"
VARS_DIR="${SCRIPT_DIR}/vars"
BUILD_SCRIPT="${KUBE_PROM_DIR}/build.sh"

pass=0
fail=0
failures=()

for version_dir in "${VARS_DIR}"/*/; do
  version="$(basename "${version_dir}")"
  echo "Version: ${version}"

  for vars_file in "${version_dir}"*.jsonnet; do
    name="$(basename "${vars_file}" .jsonnet)"
    outdir="$(mktemp -d)"

    cluster_dir="${outdir}/cluster"
    mkdir -p "${cluster_dir}"
    cp "${vars_file}" "${cluster_dir}/${name}-vars.jsonnet"

    if bash "${BUILD_SCRIPT}" "${cluster_dir}" >"${outdir}/build.log" 2>&1; then
      echo "  PASS  ${version}/${name}"
      pass=$((pass + 1))
    else
      echo "  FAIL  ${version}/${name}"
      cat "${outdir}/build.log"
      fail=$((fail + 1))
      failures+=("${version}/${name}")
    fi

    rm -rf "${outdir}"
  done
done

echo ""
echo "Results: ${pass} passed, ${fail} failed"

if [ ${fail} -gt 0 ]; then
  echo "Failed: ${failures[*]}"
  exit 1
fi

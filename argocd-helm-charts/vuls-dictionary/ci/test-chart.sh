#!/usr/bin/env bash
# CI test script for the vuls-dictionary Helm chart.
# Runs helm template with various value combinations to verify the chart renders correctly.
set -euo pipefail

CHART_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE_NAME="test"
PASS=0
FAIL=0

run_test() {
  local desc="$1"
  shift
  echo -n "TEST: ${desc} ... "
  if output=$(helm template "$RELEASE_NAME" "$CHART_DIR" "$@" 2>&1); then
    echo "PASS"
    PASS=$((PASS + 1))
  else
    echo "FAIL"
    echo "$output"
    FAIL=$((FAIL + 1))
  fi
}

assert_present() {
  local desc="$1"
  local pattern="$2"
  shift 2
  echo -n "TEST: ${desc} ... "
  if helm template "$RELEASE_NAME" "$CHART_DIR" "$@" 2>&1 | grep -q "$pattern"; then
    echo "PASS"
    PASS=$((PASS + 1))
  else
    echo "FAIL (expected pattern: ${pattern})"
    FAIL=$((FAIL + 1))
  fi
}

assert_absent() {
  local desc="$1"
  local pattern="$2"
  shift 2
  echo -n "TEST: ${desc} ... "
  if helm template "$RELEASE_NAME" "$CHART_DIR" "$@" 2>&1 | grep -q "$pattern"; then
    echo "FAIL (unexpected pattern found: ${pattern})"
    FAIL=$((FAIL + 1))
  else
    echo "PASS"
    PASS=$((PASS + 1))
  fi
}

echo "=== vuls-dictionary Helm chart CI tests ==="
echo ""

# --- Default values ---
run_test "default values render successfully"

assert_present "default: CVE image tag is v0.16.0" "vuls/go-cve-dictionary:v0.16.0"
assert_present "default: OVAL image tag is v0.15.1" "vuls/goval-dictionary:v0.15.1"
assert_present "default: vuls-server deployment present" "vuls-server"
assert_present "default: configmap present" "vuls-config"
assert_present "default: results PVC present" "results-pvc"

# --- PostgreSQL (CNPG) ---
assert_present "postgresql: CNPG Cluster created" "kind: Cluster" \
  --show-only templates/postgresql.yaml

assert_present "postgresql: cluster name correct" "test-vuls-dictionary-pgsql"

assert_present "postgresql: bootstrap database is vuls" "database: vuls"

assert_present "postgresql: dbtype postgres in deployment" "dbtype" \
  --show-only templates/deployment.yaml

assert_present "postgresql: wait-for-postgres init container" "wait-for-postgres" \
  --show-only templates/deployment.yaml

assert_present "postgresql: pgsql-app secret ref in deployment" "pgsql-app" \
  --show-only templates/deployment.yaml

assert_present "postgresql: dbtype postgres in CVE cronjob" "dbtype" \
  --show-only templates/cronjobs-cve.yaml

assert_present "postgresql: dbtype postgres in OVAL cronjob" "dbtype" \
  --show-only templates/cronjobs-oval.yaml

assert_present "postgresql: dbtype postgres in CVE seed hook" "dbtype" \
  --show-only templates/hook-cve-seed.yaml

# --- vulsServer enabled ---
run_test "vulsServer enabled renders successfully" \
  --set vulsServer.enabled=true

assert_present "vulsServer: deployment created" "test-vuls-dictionary-vuls-server" \
  --set vulsServer.enabled=true

assert_present "vulsServer: service created" "kind: Service" \
  --set vulsServer.enabled=true

assert_present "vulsServer: configmap created" "vuls-config" \
  --set vulsServer.enabled=true

assert_present "vulsServer: results PVC created" "results-pvc" \
  --set vulsServer.enabled=true

assert_present "vulsServer: image is vuls/vuls:v0.38.6" "vuls/vuls:v0.38.6" \
  --set vulsServer.enabled=true

assert_present "vulsServer: listens on port 5515" "containerPort: 5515" \
  --set vulsServer.enabled=true

# --- config.toml URLs point to dictionary services ---
assert_present "config.toml: CVE dict URL correct" "http://test-vuls-dictionary-dict-server:1323" \
  --set vulsServer.enabled=true

assert_present "config.toml: OVAL dict URL correct" "http://test-vuls-dictionary-dict-server:1324" \
  --set vulsServer.enabled=true

# --- Ingress variations ---
run_test "ingress disabled (default)" \
  --set ingress.enabled=false

assert_absent "ingress disabled: no Ingress resource" "kind: Ingress" \
  --set ingress.enabled=false

run_test "ingress enabled without vuls-server" \
  --set ingress.enabled=true

assert_absent "ingress without vulsServer: no vuls-server backend in ingress" "vuls-server" \
  --set ingress.enabled=true \
  --show-only templates/ingress.yaml

run_test "ingress enabled with vuls-server" \
  --set vulsServer.enabled=true \
  --set ingress.enabled=true \
  --set ingress.vulsServer.enabled=true

assert_present "ingress with vulsServer: vuls-server backend present" "test-vuls-dictionary-vuls-server" \
  --set vulsServer.enabled=true \
  --set ingress.enabled=true \
  --set ingress.vulsServer.enabled=true

assert_present "ingress with vulsServer: port 5515 in ingress" "number: 5515" \
  --set vulsServer.enabled=true \
  --set ingress.enabled=true \
  --set ingress.vulsServer.enabled=true

# --- Disable individual dictionaries ---
run_test "CVE disabled renders successfully" \
  --set cve.enabled=false

assert_absent "CVE disabled: no CVE container in deployment" "vuls/go-cve-dictionary" \
  --set cve.enabled=false \
  --show-only templates/deployment.yaml

run_test "OVAL disabled renders successfully" \
  --set oval.enabled=false

assert_absent "OVAL disabled: no OVAL container in deployment" "vuls/goval-dictionary" \
  --set oval.enabled=false \
  --show-only templates/deployment.yaml

# --- Custom values ---
run_test "custom vuls-server port" \
  --set vulsServer.enabled=true \
  --set vulsServer.port=9999

assert_present "custom port: containerPort 9999" "containerPort: 9999" \
  --set vulsServer.enabled=true \
  --set vulsServer.port=9999

run_test "custom results storage size" \
  --set vulsServer.enabled=true \
  --set vulsServer.resultsStorage.size=10Gi

assert_present "custom storage: 10Gi in results PVC" "storage: 10Gi" \
  --set vulsServer.enabled=true \
  --set vulsServer.resultsStorage.size=10Gi

# --- Summary ---
echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

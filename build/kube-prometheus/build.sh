#!/usr/bin/env bash
#

# This script requires path to cluster folder in clone of customers
# kubernetes-config repo in arg $1. The folder should contain a
# <cluster-name>-vars.jsonnet file. With CAPI, the folder name can be
# different from the cluster name (e.g., folder: staging.local.example.com,
# cluster name: staging, jsonnet file: staging-vars.jsonnet).
# The manifests will be put in the cluster folder in a kube-prometheus subdir.
# And it must be run from the root of the argocd-apps repo. Example:
# ./build/kube-prometheus/build.sh ../kubernetes-config-enableit/k8s/kam.obmondo.com

set -euo pipefail

declare -i debug=0 \
  commit=0

declare cluster_dir=''

function realpath() {
  [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}

basedir="$(dirname "$(realpath "${0}")")"

function _exit() {
  if ! ((debug)); then
    if [ -v tmpdir ] && [ -d "${tmpdir}" ]; then
      rm -rf "${tmpdir}"
    fi
  fi
}

trap _exit EXIT

function usage() {
  cat <<EOF
${0} [-d|--debug] <CLUSTER>

Compile kube-prometheus manifests from jsonnet template.

Arguments:
  -d|--debug
    Leave temporary output folder when exiting.
  --commit
    Commit the generated manifests in the kubeaid-config repo.
EOF
}

while (($# > 0)); do
  case "${1}" in
  -d | --debug)
    debug=1
    ;;
  --commit)
    commit=1
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    if ! [ -d "${1}" ]; then
      echo "Invalid argument ${1}"
      exit 2
    fi
    cluster_dir="${1}"
    ;;
  esac
  shift
done

if ! [[ "${cluster_dir}" ]]; then
  echo "Missing argument cluster_dir"
  exit 2
fi

# Find the vars.jsonnet file in the cluster directory
# With CAPI, folder name can differ from cluster name
cluster_jsonnet=$(find "${cluster_dir}" -maxdepth 1 -name "*-vars.jsonnet" -type f | head -n 1)

if [ -z "${cluster_jsonnet}" ]; then
  echo "No vars.jsonnet file found in ${cluster_dir}"
  echo "Expected a file named <cluster-name>-vars.jsonnet"
  exit 2
fi

# Sanity checks for jsonnet version
if ! tmp=$(jsonnet --version 2>&1); then
  echo "Missing the program 'jsonnet'"
  exit 2
fi
if ! [[ "${tmp}" =~ v([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
  echo "Unable to parse jsonnet version ('${tmp}')"
  exit 2
fi

declare -i _version=$(((BASH_REMATCH[1] * 10 ** 6) + (BASH_REMATCH[2] * 10 ** 3) + BASH_REMATCH[3]))
if ((_version < 18000)); then
  echo "jsonnet version too old; aborting"
  exit 2
fi

# Make sure to use project tooling
outdir="${cluster_dir%/}/kube-prometheus"

# NOTE: If 'kube_prometheus_version' isn't specified in the customer values file ($cluster_jsonnet),
# then we're setting 'main' as the default tag for it.
# You can always specify it to get the specific version/tag build by specifying `kube_prometheus_version`
# in the customer values file.
kube_prometheus_release=$(jsonnet "${cluster_jsonnet}" | jq -e -r '.kube_prometheus_version // "main"')
if [[ -z "${kube_prometheus_release}" ]]; then
  echo "Unable to parse kube-prometheus version, please verify '${cluster_jsonnet}'"
  exit 3
fi

jsonnet_lib_path="${basedir}/libraries/${kube_prometheus_release}/vendor"

function jb_install() {
  package_name=$1
  package_url=$2

  if ! [[ -d "${jsonnet_lib_path}/${package_name}" ]]; then
    jb install "$package_url"
  fi
}

function build_for_tag() {
  local kube_prometheus_release_tag="$1"
  echo "Processing For Tag: $kube_prometheus_release_tag"

  jb init
  jb_install kube-prometheus "github.com/prometheus-operator/kube-prometheus/jsonnet/kube-prometheus@${kube_prometheus_release_tag}"
  jb_install prometheus-mixin "github.com/bitnami-labs/sealed-secrets/contrib/prometheus-mixin@main"
  jb_install ceph-mixins "github.com/ceph/ceph/monitoring/ceph-mixin@main"
  jb_install cert-manager-mixin "gitlab.com/uneeq-oss/cert-manager-mixin@master"
  jb_install opensearch-mixin "github.com/grafana/jsonnet-libs/opensearch-mixin@master"
  jb_install opencost-mixin "github.com/adinhodovic/opencost-mixin@main"
  if [ "$kube_prometheus_release" == "v0.13.0" ]; then
    jb_install rabbitmq-mixin "github.com/adinhodovic/rabbitmq-mixin@master"
  else
    jb_install rabbitmq-mixin "github.com/grafana/jsonnet-libs/rabbitmq-mixin@master"
  fi
  jb_install mixin-utils "github.com/grafana/jsonnet-libs/mixin-utils@master"

  mkdir -p "${basedir}/libraries/${kube_prometheus_release_tag}"
  mv vendor "${basedir}/libraries/${kube_prometheus_release_tag}/"
  mv jsonnetfile.json jsonnetfile.lock.json "${basedir}/libraries/${kube_prometheus_release_tag}/"

  echo "Processed folder: $kube_prometheus_release_tag"
  echo
}

if ! [ -e "${jsonnet_lib_path}" ]; then
  build_for_tag "$kube_prometheus_release"
fi

CLUSTER_VARS_FILE="${cluster_jsonnet}" bash "${basedir}/tests/lint_vars_access.sh"

cluster_name=$(basename "${cluster_dir%/}")

if ((commit)); then
  _original_branch=$(git -C "${cluster_dir}" rev-parse --abbrev-ref HEAD)
  _new_branch="kube-prometheus-${cluster_name}-${kube_prometheus_release}-$(date +%Y%m%d%H%M%S)"
  git -C "${cluster_dir}" checkout -q -b "${_new_branch}"
fi

build_start=$(date +%s)

# Use a temporary directory
tmpdir=$(mktemp -d)
mkdir "${tmpdir}/setup"

# Compile jsonnet files
# shellcheck disable=SC2016
jsonnet -J \
  "${jsonnet_lib_path}" \
  --ext-code-file vars="${cluster_jsonnet}" \
  -m "${tmpdir}" \
  "${basedir}/common-template.jsonnet" |
  while read -r f; do
    gojsontoyaml <"${f}" >"${f}.yaml"
    rm "${f}"
  done

rm -rf "${outdir}"
mv "${tmpdir}" "${outdir}"

build_end=$(date +%s)
echo "Successfully built for ${cluster_name} (kube-prometheus ${kube_prometheus_release}) in $((build_end - build_start))s → ${outdir}"

if ((commit)); then
  if git -C "${cluster_dir}" diff --quiet -- kube-prometheus/ && git -C "${cluster_dir}" diff --cached --quiet -- kube-prometheus/; then
    echo "Nothing to commit in ${cluster_dir}/kube-prometheus"
    git -C "${cluster_dir}" checkout -q "${_original_branch}"
    git -C "${cluster_dir}" branch -q -d "${_new_branch}"
  else
    git -C "${cluster_dir}" add kube-prometheus/
    echo ""
    git -C "${cluster_dir}" diff --cached --stat
    echo ""

    if command -v gpg >/dev/null 2>&1 && gpg --card-status >/dev/null 2>&1; then
      echo "  >>> Touch your YubiKey to sign the commit <<<"
      echo ""
    fi

    if ! git -C "${cluster_dir}" commit -m "kube-prometheus: rebuild manifests for ${cluster_name} (${kube_prometheus_release})" 2>/dev/null; then
      echo "ERROR: GPG signing failed — YubiKey not touched in time or cancelled"
      echo ""
      echo "  Branch: ${_new_branch}"
      echo "  Retry:  git -C '${cluster_dir}' checkout '${_new_branch}' && git commit"
      git -C "${cluster_dir}" checkout -q "${_original_branch}"
      exit 1
    fi

    git -C "${cluster_dir}" checkout -q "${_original_branch}"

    echo ""
    read -rp "Push branch '${_new_branch}' or rebase into '${_original_branch}'? [push/rebase] " _action
    case "${_action}" in
    push)
      git -C "${cluster_dir}" push origin "${_new_branch}"
      ;;
    rebase)
      git -C "${cluster_dir}" rebase "${_new_branch}"
      git -C "${cluster_dir}" branch -d "${_new_branch}"
      ;;
    *)
      echo "Unknown action '${_action}', branch '${_new_branch}' left as-is"
      ;;
    esac
  fi
fi

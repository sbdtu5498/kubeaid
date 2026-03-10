#!/usr/bin/env bash

set -euo pipefail

if [[ -z "$1" ]]; then
  echo "Usage: $0 <target-directory>"
  exit 1
fi

RUN_ONLY="all"

echo "Do you want to:"
echo "1) Type MASTER_PASSWORD manually"
echo "2) Use existing SealedSecret to pick the password"
read -r -p "Enter choice [1/2]: " choice

case "$choice" in
  1)
    # Manual input
    read -r -p "Enter MASTER_PASSWORD (use the same one from previous SealedSecret if you want to regenerate): " MASTER_PASSWORD
    echo
    ;;
  2)
    # Pull from existing SealedSecret
    read -r -p "Enter name of existing SealedSecret (e.g., opendesk-master-password): " SECRET_NAME
    MASTER_PASSWORD=$(kubectl get secret "$SECRET_NAME" -n opendesk -o jsonpath='{.data.MASTER_PASSWORD}' | base64 --decode)
    if [ -z "$MASTER_PASSWORD" ]; then
      echo "Error: Secret not found or empty!"
      exit 1
    fi
    echo "MASTER_PASSWORD retrieved from SealedSecret $SECRET_NAME"
    ;;
  *)
    echo "Invalid choice, exiting"
    exit 1
    ;;
esac

# Export for Helm rendering
export MASTER_PASSWORD
# Allowed app names
VALID_APPS=("essentials" "mail" "chat" "jitsi" "nextcloud" "openproject" "xwiki")

if [[ -n "${2:-}" ]]; then
  if [[ "${2}" =~ ^--only-(.+)$ ]]; then
    REQUESTED="${BASH_REMATCH[1]}"

    if [[ " ${VALID_APPS[*]} " =~ ${REQUESTED} ]]; then
      RUN_ONLY="$REQUESTED"
    else
      echo "Invalid option: ${2}"
      exit 1
    fi
  else
    echo "Invalid option format: ${2}"
    exit 1
  fi
fi

echo "Running: $RUN_ONLY"


if [[ "$1" == "--help" ]]; then
  cat <<EOF
Usage:
  $0 <target-directory> [OPTIONS]

Description:
  Generates Opendesk manifests using helmfile.

Arguments:
  <target-directory>   Absolute path to kubeaid-config values directory.

Options:
  (no option)              Generate all Opendesk manifests (default)

  --all                    Generate all Opendesk manifests
  --only-essentials        Generate only core essential apps
  --only-nextcloud         Generate only Nextcloud related apps
  --only-mail              Generate only mail apps
  --only-chat              Generate only chat apps
  --only-openproject       Generate only OpenProject apps
  --only-xwiki             Generate only XWiki apps
  --only-jitsi             Generate only Jitsi apps

  --help                   Show this help message and exit


EOF
  exit 0
fi

TARGET_DIR="$1"
VALUES_FILE="$TARGET_DIR/values-opendesk.yaml"
OPENDESK_DIR="$TARGET_DIR/../opendesk"
ESSENTIALS_DIR="$TARGET_DIR/../opendesk-essentials"

mkdir -p "$OPENDESK_DIR"/{chat,mail,nextcloud,openproject,xwiki,jitsi}
mkdir -p "$ESSENTIALS_DIR"

# Change to the appropriate version directory
cd "versions/v1.11.4"

generate_selector_flags() {
    local apps_list="$1"
    local flags=()
    # Read the comma separated list into an array
    IFS=',' read -r -a APP_ARRAY <<< "$apps_list"

    # Build an array of selector flags
    for app_name in "${APP_ARRAY[@]}"; do
        flags+=("--selector" "name=$app_name")
    done
    # Echo flags for command substitution
    echo "${flags[@]}"
}

CORE_APPS="postgresql,mariadb,redis,memcached,minio,nginx-s3-gateway,cassandra,nubus,ums,opendesk-keycloak-bootstrap,intercom-service,opendesk-certificates,clamav,clamav-simple,opendesk-otterize,opendesk-static-files,opendesk-well-known,migrations-pre,migrations-post,opendesk-home,opendesk-alerts,opendesk-dashboards"

OPENDESK_FILES="opendesk-nextcloud,opendesk-nextcloud-management,opendesk-nextcloud-notifypush,collabora-online,collabora-controller,cryptpad,notes"

OPENDESK_MAIL="postfix,postfix-ox,dovecot,opendesk-dkimpy-milter,open-xchange,opendesk-open-xchange-bootstrap,ox-connector"

OPENDESK_CHAT="opendesk-element,opendesk-synapse,opendesk-synapse-web,opendesk-synapse-adminbot-bootstrap,opendesk-synapse-auditbot-bootstrap,opendesk-synapse-adminbot-web,opendesk-synapse-adminbot-pipe,opendesk-synapse-auditbot-pipe,matrix-user-verification-service-bootstrap,matrix-user-verification-service,matrix-neoboard-widget,matrix-neochoice-widget,matrix-neodatefix-widget,matrix-neodatefix-bot-bootstrap,matrix-neodatefix-bot"

OPENDESK_PROJECTS="opendesk-openproject-bootstrap,openproject,opendesk-synapse-admin,opendesk-synapse-groupsync"

OPENDESK_VIDEO="jitsi"

OPENDESK_XWIKI="xwiki"

if [[ "$RUN_ONLY" == "all" || "$RUN_ONLY" == "essentials" ]]; then
# Disable shell check in commands, we need word splitting for multiple helmfile selector flags
echo "Generating core essential apps manifest..."

# shellcheck disable=SC2046
helmfile template -e default -n opendesk --state-values-file "../../default-values/values.yaml" --state-values-file "${VALUES_FILE}" \
  $(generate_selector_flags "$CORE_APPS") > "${ESSENTIALS_DIR}/opendesk-essentials.yaml"  
fi
if [[ "$RUN_ONLY" == "all" || "$RUN_ONLY" == "nextcloud" ]]; then
echo "Generating nextcloud manifest..."

# shellcheck disable=SC2046
helmfile template -e default -n opendesk --state-values-file "../../default-values/values.yaml" --state-values-file "${VALUES_FILE}" \
  $(generate_selector_flags "$OPENDESK_FILES") > "${OPENDESK_DIR}/nextcloud/nextcloud.yaml"
fi
if [[ "$RUN_ONLY" == "all" || "$RUN_ONLY" == "chat" ]]; then
echo "Generating matrix chat manifest..."

# shellcheck disable=SC2046
helmfile template -e default -n opendesk --state-values-file "../../default-values/values.yaml" --state-values-file "${VALUES_FILE}" \
  $(generate_selector_flags "$OPENDESK_CHAT") > "${OPENDESK_DIR}/chat/chat.yaml"

fi
if [[ "$RUN_ONLY" == "all" || "$RUN_ONLY" == "mail" ]]; then
echo "Generating mail manifest..."

# shellcheck disable=SC2046
helmfile template -e default -n opendesk --state-values-file "../../default-values/values.yaml" --state-values-file "${VALUES_FILE}" \
  $(generate_selector_flags "$OPENDESK_MAIL") > "${OPENDESK_DIR}/mail/mail.yaml"
fi
if [[ "$RUN_ONLY" == "all" || "$RUN_ONLY" == "openproject" ]]; then
echo "Generating openproject manifest..."


# shellcheck disable=SC2046
helmfile template -e default -n opendesk --state-values-file "../../default-values/values.yaml" --state-values-file "${VALUES_FILE}" \
  $(generate_selector_flags "$OPENDESK_PROJECTS") > "${OPENDESK_DIR}/openproject/openproject.yaml"

fi
if [[ "$RUN_ONLY" == "all" || "$RUN_ONLY" == "xwiki" ]]; then
echo "Generating xwiki manifest..."

# shellcheck disable=SC2046
helmfile template -e default -n opendesk --state-values-file "../../default-values/values.yaml" --state-values-file "${VALUES_FILE}" \
  $(generate_selector_flags "$OPENDESK_XWIKI") > "${OPENDESK_DIR}/xwiki/xwiki.yaml"

fi
if [[ "$RUN_ONLY" == "all" || "$RUN_ONLY" == "jitsi" ]]; then
echo "Generating jitsi manifest..."

# shellcheck disable=SC2046
helmfile template -e default -n opendesk --state-values-file "../../default-values/values.yaml" --state-values-file "${VALUES_FILE}" \
  $(generate_selector_flags "$OPENDESK_VIDEO") > "${OPENDESK_DIR}/jitsi/jitsi.yaml"

fi

# Fix hook annotations and ttlSecondsAfterFinished for both files
fix_hooks_and_ttl() {
  local file=$1
  echo "fixing $file"
  sed -i \
    -e 's/helm\.sh\/hook: .*/"managed-by": "helmfile"/g' \
    -e 's/"helm\.sh\/hook": .*/"argocd.argoproj.io\/hook": "Sync"/g' \
    -e 's/"argocd.argoproj.io\/hook":.*/"managed-by": "helmfile"/g' \
    -e 's/argocd.argoproj.io\/hook:.*/"managed-by": "helmfile"/g' \
    -e '/helm\.sh\/hook-delete-policy/d' \
    -e '/argocd.argoproj.io\/hook-delete-policy/d' \
    -e '/ttlSecondsAfterFinished/d' \
    "$file"
  echo "Fixed hooks and TTL in $file"
}

fix_hooks_and_ttl "${ESSENTIALS_DIR}/opendesk-essentials.yaml"
fix_hooks_and_ttl "${OPENDESK_DIR}/nextcloud/nextcloud.yaml"
fix_hooks_and_ttl "${OPENDESK_DIR}/chat/chat.yaml"
fix_hooks_and_ttl "${OPENDESK_DIR}/mail/mail.yaml"
fix_hooks_and_ttl "${OPENDESK_DIR}/openproject/openproject.yaml"
fix_hooks_and_ttl "${OPENDESK_DIR}/xwiki/xwiki.yaml"
fix_hooks_and_ttl "${OPENDESK_DIR}/jitsi/jitsi.yaml"

# Append static template only to dependent apps
cat ../../templates/openebs-tmp-hostpath.yaml >> "${ESSENTIALS_DIR}/opendesk-essentials.yaml"

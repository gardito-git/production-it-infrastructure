#!/bin/bash
# Shared helpers, sourced by every other script in this folder.
# /etc/monitoring-bootstrap/env is written by user-data.sh.tftpl at first boot.
set -euo pipefail

# shellcheck source=/dev/null
source /etc/monitoring-bootstrap/env
export AWS_DEFAULT_REGION="$AWS_REGION"
export PATH="$PATH:/snap/bin:/usr/local/bin"
export DEBIAN_FRONTEND=noninteractive
export HOME=${HOME:-/root} # cloud-init runs user data without HOME; the AWS CLI needs it

SCRIPT_DIR=/opt/monitoring-bootstrap
DATA_DIR=/data
APT=(apt-get -o DPkg::Lock::Timeout=600 -y -q)

log() {
  echo "[$(date -u +%FT%TZ)] [monitoring] $*"
}

die() {
  log "ERROR: $*"
  exit 1
}

# secret_field ARN FIELD: one field of a Secrets Manager secret ("" if unset).
secret_field() {
  aws secretsmanager get-secret-value --secret-id "$1" --query SecretString --output text 2>/dev/null |
    jq -r --arg f "$2" '.[$f] // empty' 2>/dev/null || true
}

# admin_password: retries, because new IAM permissions can take a minute to
# reach a fresh instance.
admin_password() {
  local value attempt
  for attempt in {1..20}; do
    value=$(secret_field "$ADMIN_SECRET_ARN" password)
    [[ -n $value ]] && { echo "$value"; return 0; }
    sleep 15
  done
  die "could not read the admin password from $ADMIN_SECRET_ARN"
}

# grafana METHOD PATH [JSON]: call PMM's Grafana API as admin. The password goes
# through a file descriptor, never on the command line.
grafana() {
  curl -fsSk -X "$1" "https://127.0.0.1:443/graph/api$2" -H 'Content-Type: application/json' \
    ${3:+-d "$3"} --config <(printf 'user = "admin:%s"\n' "$PMM_ADMIN_PASSWORD")
}

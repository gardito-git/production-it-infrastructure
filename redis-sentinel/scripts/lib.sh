#!/bin/bash
# Shared helpers, sourced by every other script in this folder.
# /etc/redis-bootstrap/env is written by user-data.sh.tftpl at first boot.
set -euo pipefail

# shellcheck source=/dev/null
source /etc/redis-bootstrap/env
export AWS_DEFAULT_REGION="$AWS_REGION"
export PATH="$PATH:/snap/bin:/usr/local/bin"
export DEBIAN_FRONTEND=noninteractive
export HOME=${HOME:-/root} # cloud-init runs user data without HOME; the AWS CLI needs it

SCRIPT_DIR=/opt/redis-bootstrap
APT=(apt-get -o DPkg::Lock::Timeout=600 -y -q)

log() {
  echo "[$(date -u +%FT%TZ)] [$NODE_NAME] $*"
}

die() {
  log "ERROR: $*"
  exit 1
}

# imds PATH: read instance metadata with IMDSv2 (the instances require tokens).
imds() {
  local token
  token=$(curl -sf -X PUT http://169.254.169.254/latest/api/token \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
  curl -sf -H "X-aws-ec2-metadata-token: $token" "http://169.254.169.254/latest/meta-data/$1"
}

# secret FIELD: read one field of the cluster's Secrets Manager secret.
# Retries because new IAM permissions can take a minute to reach a fresh instance.
secret() {
  local attempt value
  for attempt in {1..20}; do
    if value=$(aws secretsmanager get-secret-value --secret-id "$SECRET_ARN" \
      --query SecretString --output text 2>/dev/null); then
      jq -er --arg f "$1" '.[$f]' <<<"$value" && return 0
    fi
    sleep 15
  done
  die "could not read $1 from $SECRET_ARN"
}

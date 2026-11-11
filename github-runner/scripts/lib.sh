#!/bin/bash
# Shared helpers, sourced by every other script in this folder.
# /etc/github-runner-bootstrap/env is written by user-data.sh.tftpl at first boot.
set -euo pipefail

# shellcheck source=/dev/null
source /etc/github-runner-bootstrap/env
export AWS_DEFAULT_REGION="$AWS_REGION"
# A fixed PATH: the runner records it at registration, and jobs inherit it
# (including /snap/bin for the AWS CLI).
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin"
export DEBIAN_FRONTEND=noninteractive
export HOME=${HOME:-/root} # cloud-init runs user data without HOME; the AWS CLI needs it

SCRIPT_DIR=/opt/github-runner-bootstrap
APT=(apt-get -o DPkg::Lock::Timeout=600 -y -q)

log() {
  echo "[$(date -u +%FT%TZ)] [$RUNNER_NAME] $*"
}

die() {
  log "ERROR: $*"
  exit 1
}

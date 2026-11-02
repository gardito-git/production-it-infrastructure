#!/bin/bash
# Shared helpers, sourced by every other script in this folder.
# /etc/k8s-bootstrap/env is written by user-data.sh.tftpl at first boot.
set -euo pipefail

# shellcheck source=/dev/null
source /etc/k8s-bootstrap/env
export AWS_DEFAULT_REGION="$AWS_REGION"
export PATH="$PATH:/snap/bin:/usr/local/bin"
export DEBIAN_FRONTEND=noninteractive
export HOME=${HOME:-/root} # cloud-init runs user data without HOME; the AWS and cilium CLIs need it

SCRIPT_DIR=/opt/k8s-bootstrap
APT=(apt-get -o DPkg::Lock::Timeout=600 -y -q)

log() {
  echo "[$(date -u +%FT%TZ)] [$NODE_ROLE-$((NODE_INDEX + 1))] $*"
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

# s3_put FILE KEY: upload a bootstrap artifact to the private bucket.
# Retries because new IAM permissions can take a minute to reach a fresh instance.
s3_put() {
  local attempt
  for attempt in {1..10}; do
    aws s3 cp --only-show-errors --sse AES256 "$1" "s3://$BOOTSTRAP_BUCKET/$2" && return 0
    log "Upload of $2 failed (attempt $attempt), retrying"
    sleep 15
  done
  die "could not upload $2"
}

# s3_wait KEY DEST [TIMEOUT]: poll until another node has uploaded KEY.
# This is how the nodes wait for each other without any boot ordering in Terraform.
s3_wait() {
  local key=$1 dest=$2 timeout=${3:-3600} waited=0
  log "Waiting for s3://$BOOTSTRAP_BUCKET/$key"
  until aws s3 cp --only-show-errors "s3://$BOOTSTRAP_BUCKET/$key" "$dest" 2>/dev/null; do
    if ((waited >= timeout)); then
      die "timed out after ${timeout}s waiting for $key"
    fi
    sleep 15
    waited=$((waited + 15))
  done
}

# wait_tcp HOST PORT [TIMEOUT]: poll until HOST:PORT accepts connections.
wait_tcp() {
  local host=$1 port=$2 timeout=${3:-1800} waited=0
  log "Waiting for $host:$port"
  until timeout 3 bash -c "</dev/tcp/$host/$port" 2>/dev/null; do
    if ((waited >= timeout)); then
      die "timed out after ${timeout}s waiting for $host:$port"
    fi
    sleep 10
    waited=$((waited + 10))
  done
}

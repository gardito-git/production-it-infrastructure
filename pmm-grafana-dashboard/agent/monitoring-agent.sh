# (The lines above this one are added by agent.tf: PMM_HOST, TOKEN_SECRET_ARN,
# LOKI_PUSH_URL, PROMETHEUS_REMOTE_WRITE_URL, AGENT_AWS_REGION, PMM_ENVIRONMENT.)
#
# Installs the monitoring agents on this server and registers it:
#   pmm-client  (pmm-agent + exporters) pushes Linux and database metrics to PMM
#   alloy       ships the systemd journal and chosen log files to Loki
#
# Usage:
#   monitoring-agent install NODE_NAME SERVICE "LOG_GLOBS" [HOOK]
#   monitoring-agent register          (run by monitoring-register.timer)
#
# NODE_NAME  how this server appears in PMM and Loki, e.g. redis-1
# SERVICE    a label for grouping, e.g. redis
# LOG_GLOBS  space-separated log files Alloy follows on top of the journal,
#            e.g. "/var/log/nginx/*.log" ("" = journal only)
# HOOK       optional script that registers this server's databases/exporters
#            with PMM (pmm-admin add ...). Exits non-zero to be retried later.
#
# Registration retries every 5 minutes until the PMM server is up and has
# published its token, so servers and the monitoring server can boot in any order.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
export PATH="$PATH:/snap/bin:/usr/local/bin:/usr/local/sbin"
export HOME=${HOME:-/root}
export AWS_DEFAULT_REGION="$AGENT_AWS_REGION"

AGENT=/usr/local/sbin/monitoring-agent
ENV_FILE=/etc/monitoring-agent/env
REGISTERED=/var/lib/monitoring-agent.registered
APT=(apt-get -o DPkg::Lock::Timeout=600 -y -q)

log() { echo "[$(date -u +%FT%TZ)] [monitoring-agent] $*"; }

install_agents() {
  local node_name=$1 service=$2 log_globs=$3 hook=${4:-}

  log "Installing monitoring agents for $node_name ($service)"
  mkdir -p /etc/monitoring-agent
  # Remember everything, also for the Kubernetes and database hooks.
  cat >"$ENV_FILE" <<EOF
NODE_NAME="$node_name"
SERVICE="$service"
HOOK="$hook"
PMM_HOST="$PMM_HOST"
PMM_ENVIRONMENT="$PMM_ENVIRONMENT"
LOKI_PUSH_URL="$LOKI_PUSH_URL"
PROMETHEUS_REMOTE_WRITE_URL="$PROMETHEUS_REMOTE_WRITE_URL"
EOF
  install -m 0755 "$0" "$AGENT"

  "${APT[@]}" install ca-certificates curl gnupg jq
  command -v aws >/dev/null || snap install aws-cli --classic

  # PMM Client from Percona's repository (pmm3-client).
  if ! command -v pmm-admin >/dev/null; then
    curl -fsSL --retry 5 -o /tmp/percona-release.deb https://repo.percona.com/apt/percona-release_latest.generic_all.deb
    "${APT[@]}" install /tmp/percona-release.deb
    rm -f /tmp/percona-release.deb
    percona-release enable pmm3-client
    "${APT[@]}" update
    "${APT[@]}" install pmm-client
    apt-mark hold pmm-client >/dev/null
  fi

  # Grafana Alloy from Grafana's repository.
  if ! command -v alloy >/dev/null; then
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL --retry 5 https://apt.grafana.com/gpg.key | gpg --dearmor --yes -o /etc/apt/keyrings/grafana.gpg
    echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" \
      >/etc/apt/sources.list.d/grafana.list
    "${APT[@]}" update
    "${APT[@]}" install alloy
  fi

  write_alloy_config "$node_name" "$service" "$log_globs"
  # Alloy reads logs owned by many services (postgres, mongodb, nginx...); as
  # root it needs no group juggling. It only reads and forwards.
  mkdir -p /etc/systemd/system/alloy.service.d
  cat >/etc/systemd/system/alloy.service.d/root.conf <<'EOF'
[Service]
User=root
EOF

  cat >/etc/systemd/system/monitoring-register.service <<EOF
[Unit]
Description=Register this server with PMM (retried until it works)
After=network-online.target pmm-agent.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$AGENT register
EOF
  cat >/etc/systemd/system/monitoring-register.timer <<'EOF'
[Unit]
Description=Retry PMM registration

[Timer]
OnBootSec=1min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable alloy
  systemctl restart alloy
  systemctl enable --now monitoring-register.timer
  "$AGENT" register || log "Not registered yet; monitoring-register.timer keeps retrying"
}

write_alloy_config() {
  local node_name=$1 service=$2 log_globs=$3 targets="" glob
  for glob in $log_globs; do
    targets+="    {\"__path__\" = \"$glob\", \"job\" = \"files\"},"$'\n'
  done

  cat >/etc/alloy/config.alloy <<EOF
// Written by monitoring-agent. Ships this server's logs to Loki.

loki.write "loki" {
  endpoint {
    url = "$LOKI_PUSH_URL"
  }
  external_labels = {
    host        = "$node_name",
    service     = "$service",
    environment = "$PMM_ENVIRONMENT",
  }
}

// Everything systemd collects: services, kernel, sshd, cloud-init...
loki.relabel "journal" {
  forward_to = []
  rule {
    source_labels = ["__journal__systemd_unit"]
    target_label  = "unit"
  }
  rule {
    source_labels = ["__journal_priority_keyword"]
    target_label  = "level"
  }
}

loki.source.journal "journal" {
  forward_to    = [loki.write.loki.receiver]
  relabel_rules = loki.relabel.journal.rules
  max_age       = "12h"
  labels        = { job = "journal" }
}
EOF

  if [[ -n $targets ]]; then
    cat >>/etc/alloy/config.alloy <<EOF

// Log files of services that don't log to the journal.
local.file_match "files" {
  path_targets = [
$targets  ]
}

loki.source.file "files" {
  targets    = local.file_match.files.targets
  forward_to = [loki.write.loki.receiver]
}
EOF
  fi
}

register() {
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  if [[ -f $REGISTERED ]]; then
    systemctl disable --now monitoring-register.timer 2>/dev/null || true
    return 0
  fi

  local token my_ip imds_token
  token=$(aws secretsmanager get-secret-value --secret-id "$TOKEN_SECRET_ARN" \
    --query SecretString --output text 2>/dev/null | jq -r '.token // empty' 2>/dev/null || true)
  if [[ -z $token ]]; then
    log "PMM has not published its agent token yet; will retry"
    return 1
  fi

  if ! pmm-admin status >/dev/null 2>&1; then
    imds_token=$(curl -sf -X PUT http://169.254.169.254/latest/api/token -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
    my_ip=$(curl -sf -H "X-aws-ec2-metadata-token: $imds_token" http://169.254.169.254/latest/meta-data/local-ipv4)
    log "Registering $NODE_NAME ($my_ip) with PMM at $PMM_HOST"
    # Push mode: this server sends its metrics to PMM over HTTPS (443), so PMM
    # never has to connect in. PMM uses its own self-signed certificate.
    pmm-admin config --server-insecure-tls --metrics-mode=push --force \
      --server-url="https://service_token:$token@$PMM_HOST:443" \
      "$my_ip" generic "$NODE_NAME" >/dev/null
  fi

  # Databases and exporters on this server (module-specific).
  if [[ -n ${HOOK:-} && -x $HOOK ]]; then
    "$HOOK" || {
      log "$HOOK not finished yet; will retry"
      return 1
    }
  fi

  touch "$REGISTERED"
  systemctl disable --now monitoring-register.timer 2>/dev/null || true
  log "Registered with PMM"
}

case "${1:-}" in
  install)
    shift
    install_agents "$@"
    ;;
  register) register ;;
  *)
    echo "usage: $0 install NODE_NAME SERVICE \"LOG_GLOBS\" [HOOK] | register" >&2
    exit 2
    ;;
esac

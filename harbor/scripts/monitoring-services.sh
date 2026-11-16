#!/bin/bash
# Registers Harbor's own Prometheus metrics (enabled in harbor.yml by harbor.sh,
# served on localhost:9090/metrics) with PMM. Run by monitoring-agent, retried
# until it succeeds.
source /opt/harbor-bootstrap/lib.sh
source /etc/monitoring-agent/env

PMM_SERVICE=harbor
pmm-admin list 2>/dev/null | grep -qw "$PMM_SERVICE" && exit 0
curl -fsS -o /dev/null http://127.0.0.1:9090/metrics || {
  log "Harbor's metrics endpoint isn't up yet"
  exit 1
}

pmm-admin add external --service-name="$PMM_SERVICE" --listen-port=9090 \
  --metrics-path=/metrics --group=harbor --environment="$PMM_ENVIRONMENT"

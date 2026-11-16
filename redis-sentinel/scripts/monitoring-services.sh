#!/bin/bash
# Registers this node's Redis with PMM (PMM 3 monitors Redis with its Valkey
# exporter). Run by monitoring-agent, retried until it succeeds.
source /opt/redis-bootstrap/lib.sh
source /etc/monitoring-agent/env

PMM_SERVICE="$NODE_NAME-redis"
pmm-admin list 2>/dev/null | grep -qw "$PMM_SERVICE" && exit 0

pmm-admin add valkey "$PMM_SERVICE" 127.0.0.1:6379 --password="$(secret password)" \
  --environment="$PMM_ENVIRONMENT" --cluster=redis-sentinel

#!/bin/bash
# Registers this node's RabbitMQ metrics with PMM: RabbitMQ's own Prometheus
# endpoint (rabbitmq_prometheus plugin, port 15692), scraped by pmm-agent as an
# external exporter. Run by monitoring-agent, retried until it succeeds.
source /opt/rabbitmq-bootstrap/lib.sh
source /etc/monitoring-agent/env

PMM_SERVICE="$NODE_NAME-rabbitmq"
pmm-admin list 2>/dev/null | grep -qw "$PMM_SERVICE" && exit 0

pmm-admin add external --service-name="$PMM_SERVICE" --listen-port=15692 \
  --metrics-path=/metrics --group=rabbitmq --environment="$PMM_ENVIRONMENT" --cluster="$CLUSTER_NAME"

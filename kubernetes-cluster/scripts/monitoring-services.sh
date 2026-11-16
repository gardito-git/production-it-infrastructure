#!/bin/bash
# Kubernetes monitoring, installed once from the first control plane node with
# Grafana's k8s-monitoring Helm chart. It runs Alloy inside the cluster and:
#   - sends cluster metrics (kube-state-metrics, kubelet, cAdvisor) to the
#     monitoring server's Prometheus (remote write)
#   - sends every pod's logs to Loki
# Every node also gets Linux monitoring and journal logs from monitoring-agent.
# Run by monitoring-agent, retried until it succeeds (e.g. while nodes join).
source /opt/k8s-bootstrap/lib.sh
source /etc/monitoring-agent/env

[[ $NODE_ROLE == control-plane && $NODE_INDEX == 0 ]] || exit 0

HELM_VERSION=3.22.1
CHART_VERSION=4.6.1
export KUBECONFIG=/etc/kubernetes/admin.conf

if ! command -v helm >/dev/null; then
  log "Installing Helm $HELM_VERSION"
  TARBALL="helm-v$HELM_VERSION-linux-amd64.tar.gz"
  cd /tmp
  curl -fsSL --retry 5 -O "https://get.helm.sh/$TARBALL" -O "https://get.helm.sh/$TARBALL.sha256sum"
  sha256sum -c "$TARBALL.sha256sum"
  tar -xzf "$TARBALL" linux-amd64/helm
  install -m 0755 linux-amd64/helm /usr/local/bin/helm
  rm -rf "$TARBALL" "$TARBALL.sha256sum" linux-amd64
fi

kubectl get nodes >/dev/null || exit 1

cat >/etc/kubernetes/k8s-monitoring-values.yaml <<EOF
# Written by monitoring-services.sh. Chart: grafana/k8s-monitoring $CHART_VERSION
cluster:
  name: $CLUSTER_NAME

destinations:
  prometheus:
    type: prometheus
    url: $PROMETHEUS_REMOTE_WRITE_URL
  loki:
    type: loki
    url: $LOKI_PUSH_URL

clusterMetrics:
  enabled: true

podLogsViaLoki:
  enabled: true

collectors:
  alloy-metrics:
    presets: [small, clustered, statefulset]
  alloy-logs:
    presets: [filesystem-log-reader, daemonset]

telemetryServices:
  kube-state-metrics:
    deploy: true
EOF

log "Installing the k8s-monitoring chart $CHART_VERSION"
helm upgrade --install k8s-monitoring k8s-monitoring \
  --repo https://grafana.github.io/helm-charts --version "$CHART_VERSION" \
  --namespace monitoring --create-namespace \
  --values /etc/kubernetes/k8s-monitoring-values.yaml --wait --timeout 10m

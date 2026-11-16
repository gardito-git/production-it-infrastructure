#!/bin/bash
# Elasticsearch metrics for PMM, collected once for the whole cluster from the
# Kibana node (masters and data nodes only get Linux monitoring and logs):
#   1. a "pmm_monitor" user with read-only monitoring privileges
#   2. elasticsearch_exporter (cluster, node and index stats) on localhost:9114
#   3. registered with PMM as an external exporter
# Run by monitoring-agent, retried until it succeeds.
source /opt/es-bootstrap/lib.sh
source /etc/monitoring-agent/env

[[ $NODE_ROLE == kibana ]] || exit 0
PMM_SERVICE=elasticsearch-exporter
pmm-admin list 2>/dev/null | grep -qw "$PMM_SERVICE" && exit 0

EXPORTER_VERSION=1.11.0
read -ra DATA <<<"$DATA_IPS"
ELASTIC_PASSWORD=$(secret elastic_password)
ES_API_HOST=${DATA[0]}
ENV_FILE=/etc/elasticsearch-exporter/env

# 1. Monitoring user. Its password lives only on this node; re-running sets a new one.
mkdir -p /etc/elasticsearch-exporter
if [[ ! -f $ENV_FILE ]]; then
  MONITOR_PASSWORD=$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9')
  es_api PUT /_security/role/pmm_monitor \
    '{"cluster":["monitor"],"indices":[{"names":["*"],"privileges":["monitor","view_index_metadata"]}]}' >/dev/null
  es_api PUT /_security/user/pmm_monitor \
    "$(jq -n --arg p "$MONITOR_PASSWORD" '{password: $p, roles: ["pmm_monitor"]}')" >/dev/null
  printf 'ES_USERNAME=pmm_monitor\nES_PASSWORD=%s\n' "$MONITOR_PASSWORD" >"$ENV_FILE"
  chmod 600 "$ENV_FILE"
fi

# 2. The exporter, checked against its published SHA-256.
if [[ ! -x /usr/local/bin/elasticsearch_exporter ]]; then
  log "Installing elasticsearch_exporter $EXPORTER_VERSION"
  BASE="https://github.com/prometheus-community/elasticsearch_exporter/releases/download/v$EXPORTER_VERSION"
  TARBALL="elasticsearch_exporter-$EXPORTER_VERSION.linux-amd64.tar.gz"
  cd /tmp
  curl -fsSL --retry 5 -O "$BASE/$TARBALL" -O "$BASE/sha256sums.txt"
  grep " $TARBALL\$" sha256sums.txt | sha256sum -c -
  tar -xzf "$TARBALL"
  install -m 0755 "elasticsearch_exporter-$EXPORTER_VERSION.linux-amd64/elasticsearch_exporter" /usr/local/bin/
  rm -rf "$TARBALL" sha256sums.txt "elasticsearch_exporter-$EXPORTER_VERSION.linux-amd64"
fi

cat >/etc/systemd/system/elasticsearch-exporter.service <<EOF
[Unit]
Description=Elasticsearch exporter for PMM
After=network-online.target
Wants=network-online.target

[Service]
EnvironmentFile=$ENV_FILE
DynamicUser=yes
# Cluster-wide stats from one data node; all nodes and indices are reported.
ExecStart=/usr/local/bin/elasticsearch_exporter --es.uri=http://${DATA[0]}:9200 --es.all --es.indices --web.listen-address=127.0.0.1:9114
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now elasticsearch-exporter
systemctl restart elasticsearch-exporter

# 3. Register with PMM.
pmm-admin add external --service-name="$PMM_SERVICE" --listen-port=9114 \
  --metrics-path=/metrics --group=elasticsearch --environment="$PMM_ENVIRONMENT" --cluster="$CLUSTER_NAME"

#!/bin/bash
# Runs the three containers on one Docker network, so Grafana reaches Loki and
# Prometheus by name:
#   pmm-server  :443   Grafana, VictoriaMetrics (metrics), ClickHouse (query analytics)
#   loki        :3100  logs, stored in S3
#   prometheus  :9090  Kubernetes metrics (remote write from the cluster)
# Re-run by hand to apply a changed setting (e.g. GitHub login): containers are
# recreated, data on /data stays.
source /opt/monitoring-bootstrap/lib.sh

RETENTION_HOURS=$((RETENTION_DAYS * 24))
docker network inspect monitoring >/dev/null 2>&1 || docker network create monitoring >/dev/null

# --- PMM Server ---------------------------------------------------------------
log "Writing PMM settings"
ENV_FILE=/etc/monitoring/pmm.env
{
  echo "GF_SECURITY_ADMIN_PASSWORD=$(admin_password)"
  # PMM wants hours, in multiples of 24 (e.g. 720h, not 30d).
  echo "PMM_DATA_RETENTION=${RETENTION_HOURS}h"
  echo "PMM_METRICS_RESOLUTION=5s"
  # Everyone who logs in through GitHub starts as a Viewer; promote admins in the UI.
  echo "GF_USERS_AUTO_ASSIGN_ORG_ROLE=Viewer"
  echo "GF_SERVER_ROOT_URL=https://$DOMAIN_NAME/graph/"
} >"$ENV_FILE"

# "Sign in with GitHub", once the OAuth app is in Secrets Manager (README).
GITHUB_CLIENT_ID=$(secret_field "$GITHUB_SECRET_ARN" client_id)
GITHUB_CLIENT_SECRET=$(secret_field "$GITHUB_SECRET_ARN" client_secret)
if [[ -n $GITHUB_ORGANIZATION && -n $GITHUB_CLIENT_ID && -n $GITHUB_CLIENT_SECRET ]]; then
  log "Enabling GitHub login for members of $GITHUB_ORGANIZATION"
  cat >>"$ENV_FILE" <<EOF
GF_AUTH_GITHUB_ENABLED=true
GF_AUTH_GITHUB_CLIENT_ID=$GITHUB_CLIENT_ID
GF_AUTH_GITHUB_CLIENT_SECRET=$GITHUB_CLIENT_SECRET
GF_AUTH_GITHUB_SCOPES=user:email,read:org
GF_AUTH_GITHUB_ALLOWED_ORGANIZATIONS=$GITHUB_ORGANIZATION
GF_AUTH_GITHUB_ALLOW_SIGN_UP=true
EOF
else
  log "GitHub login not configured (organization or OAuth app missing); local users only"
fi
chmod 600 "$ENV_FILE"

log "Starting PMM Server $PMM_VERSION"
docker rm -f pmm-server >/dev/null 2>&1 || true
docker run --detach --restart always --name pmm-server --network monitoring \
  --publish 443:8443 \
  --volume "$DATA_DIR/pmm:/srv" \
  --env-file "$ENV_FILE" \
  "percona/pmm-server:$PMM_VERSION" >/dev/null

# --- Loki ---------------------------------------------------------------------
log "Writing Loki settings (logs in s3://$LOKI_BUCKET, kept $RETENTION_DAYS days)"
cat >/etc/monitoring/loki.yaml <<EOF
# Written by monitoring.sh. Single-binary Loki; chunks and index in S3.
auth_enabled: false

server:
  http_listen_port: 3100
  log_level: warn

common:
  path_prefix: /loki
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory
  storage:
    s3:
      region: $AWS_REGION
      bucketnames: $LOKI_BUCKET

schema_config:
  configs:
    - from: "2026-01-01"
      store: tsdb
      object_store: s3
      schema: v13
      index:
        prefix: index_
        period: 24h

compactor:
  working_directory: /loki/compactor
  retention_enabled: true
  delete_request_store: s3

limits_config:
  retention_period: ${RETENTION_HOURS}h
  ingestion_rate_mb: 16
  ingestion_burst_size_mb: 32
  reject_old_samples: true
  reject_old_samples_max_age: 168h
EOF
chmod 644 /etc/monitoring/loki.yaml

log "Starting Loki $LOKI_VERSION"
docker rm -f loki >/dev/null 2>&1 || true
docker run --detach --restart always --name loki --network monitoring \
  --publish 3100:3100 \
  --volume "$DATA_DIR/loki:/loki" \
  --volume /etc/monitoring/loki.yaml:/etc/loki/config.yaml:ro \
  "grafana/loki:$LOKI_VERSION" -config.file=/etc/loki/config.yaml >/dev/null

# --- Prometheus (Kubernetes only) -------------------------------------------------
cat >/etc/monitoring/prometheus.yml <<'EOF'
# Written by monitoring.sh. Kubernetes pushes its metrics here (remote write);
# Prometheus scrapes nothing but itself.
global:
  scrape_interval: 30s
scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets: ["localhost:9090"]
EOF
chmod 644 /etc/monitoring/prometheus.yml

log "Starting Prometheus $PROMETHEUS_VERSION"
docker rm -f prometheus >/dev/null 2>&1 || true
docker run --detach --restart always --name prometheus --network monitoring \
  --publish 9090:9090 \
  --volume "$DATA_DIR/prometheus:/prometheus" \
  --volume /etc/monitoring/prometheus.yml:/etc/prometheus/prometheus.yml:ro \
  "prom/prometheus:v$PROMETHEUS_VERSION" \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus \
  --storage.tsdb.retention.time="${RETENTION_DAYS}d" \
  --web.enable-remote-write-receiver >/dev/null

log "Waiting for PMM to be ready"
for attempt in {1..90}; do
  curl -fsk https://127.0.0.1:443/v1/server/readyz >/dev/null 2>&1 && break
  ((attempt == 90)) && die "PMM did not become ready; see: docker logs pmm-server"
  sleep 10
done
# Logs are a bonus: if Loki can't start (e.g. its bucket isn't reachable), metrics
# and the agent token must still come up, so this only warns.
LOKI_READY=false
for _ in {1..30}; do
  curl -fs http://127.0.0.1:3100/ready >/dev/null 2>&1 && { LOKI_READY=true; break; }
  sleep 5
done
if [[ $LOKI_READY == true ]]; then
  log "PMM, Loki and Prometheus are running"
else
  log "WARNING: Loki is not ready; logs won't arrive until it is. See: docker logs loki"
fi

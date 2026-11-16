#!/bin/bash
# Nginx metrics for PMM: Nginx's stub_status page on localhost:8081, read by
# nginx-prometheus-exporter on localhost:9113, registered with PMM as an
# external exporter. Run by monitoring-agent, retried until it succeeds.
set -euo pipefail
source /etc/monitoring-agent/env

PMM_SERVICE="$NODE_NAME-nginx"
pmm-admin list 2>/dev/null | grep -qw "$PMM_SERVICE" && exit 0
EXPORTER_VERSION=1.5.3

cat >/etc/nginx/conf.d/stub-status.conf <<'EOF'
# Connection and request counters for the Prometheus exporter; localhost only.
server {
    listen 127.0.0.1:8081;
    location = /stub_status {
        stub_status;
    }
}
EOF
nginx -t
systemctl reload nginx

if [[ ! -x /usr/local/bin/nginx-prometheus-exporter ]]; then
  BASE="https://github.com/nginx/nginx-prometheus-exporter/releases/download/v$EXPORTER_VERSION"
  TARBALL="nginx-prometheus-exporter_${EXPORTER_VERSION}_linux_amd64.tar.gz"
  cd /tmp
  curl -fsSL --retry 5 -O "$BASE/$TARBALL" -O "$BASE/nginx-prometheus-exporter_${EXPORTER_VERSION}_checksums.txt"
  grep " $TARBALL\$" "nginx-prometheus-exporter_${EXPORTER_VERSION}_checksums.txt" | sha256sum -c -
  tar -xzf "$TARBALL" nginx-prometheus-exporter
  install -m 0755 nginx-prometheus-exporter /usr/local/bin/
  rm -f "$TARBALL" nginx-prometheus-exporter "nginx-prometheus-exporter_${EXPORTER_VERSION}_checksums.txt"
fi

cat >/etc/systemd/system/nginx-exporter.service <<'EOF'
[Unit]
Description=Nginx exporter for PMM
After=nginx.service

[Service]
DynamicUser=yes
ExecStart=/usr/local/bin/nginx-prometheus-exporter --nginx.scrape-uri=http://127.0.0.1:8081/stub_status --web.listen-address=127.0.0.1:9113
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now nginx-exporter

pmm-admin add external --service-name="$PMM_SERVICE" --listen-port=9113 \
  --metrics-path=/metrics --group=nginx --environment="$PMM_ENVIRONMENT"

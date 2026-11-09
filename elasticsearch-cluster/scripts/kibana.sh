#!/bin/bash
# Runs on the Kibana node. Waits for the cluster, finishes the cluster-wide setup
# (passwords, S3 snapshot repository, daily snapshot policy), then starts Kibana.
source /opt/es-bootstrap/lib.sh

MY_IP=$(imds local-ipv4)
read -ra MASTERS <<<"$MASTER_IPS"
ES_API_HOST=${MASTERS[0]}

install_elastic_repo
log "Installing Kibana $ELASTIC_VERSION"
"${APT[@]}" install "kibana=$ELASTIC_VERSION"
apt-mark hold kibana

ELASTIC_PASSWORD=$(secret elastic_password)
KIBANA_SYSTEM_PASSWORD=$(secret kibana_system_password)

log "Waiting for the Elasticsearch cluster (at least yellow)"
for attempt in {1..180}; do
  es_api GET '/_cluster/health?wait_for_status=yellow&timeout=10s' >/dev/null 2>&1 && break
  ((attempt == 180)) && die "the cluster never became available at http://$ES_API_HOST:9200"
  sleep 10
done
log "Cluster: $(es_api GET '/_cat/health?h=cluster,status,node.total')"

# Store the elastic password in the cluster (until now it only came from each
# node's bootstrap.password), and give Kibana its own built-in user.
es_api POST /_security/user/elastic/_password "$(jq -n --arg p "$ELASTIC_PASSWORD" '{password: $p}')" >/dev/null
es_api POST /_security/user/kibana_system/_password "$(jq -n --arg p "$KIBANA_SYSTEM_PASSWORD" '{password: $p}')" >/dev/null
log "Built-in user passwords set"

log "Registering the S3 snapshot repository (s3://$BACKUP_BUCKET/$BACKUP_PREFIX)"
es_api PUT /_snapshot/s3-backups "$(jq -n --arg b "$BACKUP_BUCKET" --arg p "$BACKUP_PREFIX" \
  '{type: "s3", settings: {bucket: $b, base_path: $p, server_side_encryption: true}}')" >/dev/null

# Daily snapshot at 01:30 UTC of all indices and the cluster state. Snapshots are
# incremental; Elasticsearch deletes old ones itself (keep 30 days, 5 to 50 snapshots).
es_api PUT /_slm/policy/daily-snapshots '{
  "schedule": "0 30 1 * * ?",
  "name": "<daily-snap-{now/d}>",
  "repository": "s3-backups",
  "config": { "indices": "*", "include_global_state": true },
  "retention": { "expire_after": "30d", "min_count": 5, "max_count": 50 }
}' >/dev/null
log "Daily snapshot policy created"

DATA_HOSTS=""
for ip in $DATA_IPS; do
  DATA_HOSTS+="${DATA_HOSTS:+, }\"http://$ip:9200\""
done

log "Writing /etc/kibana/kibana.yml"
cat >/etc/kibana/kibana.yml <<EOF
# Written by kibana.sh at first boot.
server.host: "0.0.0.0"
server.port: 5601
server.name: "kibana"
# Reached over the VPN; the VPN encrypts the traffic.
server.publicBaseUrl: "http://$MY_IP:5601"

# Kibana spreads its requests over the data nodes, over plain HTTP with its own user.
elasticsearch.hosts: [ $DATA_HOSTS ]
elasticsearch.username: "kibana_system"

logging.appenders.file.type: file
logging.appenders.file.fileName: /var/log/kibana/kibana.log
logging.appenders.file.layout.type: json
logging.root.appenders: [ default, file ]
EOF

# Secrets go into Kibana's keystore, not kibana.yml.
KEYSTORE=/usr/share/kibana/bin/kibana-keystore
[[ -f /etc/kibana/kibana.keystore ]] || "$KEYSTORE" create
printf '%s' "$KIBANA_SYSTEM_PASSWORD" | "$KEYSTORE" add --stdin --force elasticsearch.password
for setting in xpack.encryptedSavedObjects.encryptionKey xpack.security.encryptionKey xpack.reporting.encryptionKey; do
  # printf: no trailing newline in the stored value.
  printf '%s' "$(secret "kibana_${setting//./_}")" | "$KEYSTORE" add --stdin --force "$setting"
done
chown -R root:kibana /etc/kibana
chmod 660 /etc/kibana/kibana.keystore /etc/kibana/kibana.yml

log "Starting Kibana"
systemctl daemon-reload
systemctl enable --now kibana

for attempt in {1..60}; do
  [[ $(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:5601/api/status") != 000 ]] && break
  ((attempt == 60)) && die "Kibana did not start; see /var/log/kibana/kibana.log"
  sleep 10
done
log "Kibana is up at http://$MY_IP:5601 (log in as elastic)"

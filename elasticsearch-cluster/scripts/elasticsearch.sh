#!/bin/bash
# Installs and starts Elasticsearch on a master or data node.
#   master nodes (3): hold the cluster state and elect a leader; store no data
#   data nodes (6):   store the indices and run searches/ingest
# Clients (apps, Kibana) use plain HTTP with a username/password. The node-to-node
# transport must have TLS switched on whenever login is enabled (Elasticsearch
# refuses to start otherwise), but nothing is verified: each node makes its own
# throwaway self-signed certificate below, and no CA or certificate is managed.
source /opt/es-bootstrap/lib.sh

MY_IP=$(imds local-ipv4)
AZ=$(imds placement/availability-zone)
ES_CONF=/etc/elasticsearch
ES_API_HOST=127.0.0.1

log "Kernel settings for Elasticsearch"
cat >/etc/sysctl.d/99-elasticsearch.conf <<'EOF'
# Elasticsearch memory-maps index files; it refuses to start below 262144.
vm.max_map_count = 1048576
# Keep the JVM heap in RAM.
vm.swappiness = 1
EOF
sysctl --system >/dev/null

install_elastic_repo
log "Installing Elasticsearch $ELASTIC_VERSION"
"${APT[@]}" install "elasticsearch=$ELASTIC_VERSION"
apt-mark hold elasticsearch

if [[ $NODE_ROLE == data ]]; then
  # Data nodes keep their indices on a separate gp3 volume. On Nitro instances it's
  # an NVMe device whose serial is the volume ID without the dash.
  DEVICE=/dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_${DATA_VOLUME_ID/-/}
  log "Waiting for data volume $DATA_VOLUME_ID"
  for _ in {1..120}; do
    [[ -e $DEVICE ]] && break
    sleep 5
  done
  [[ -e $DEVICE ]] || die "data volume $DATA_VOLUME_ID never appeared at $DEVICE"
  if ! blkid "$DEVICE" >/dev/null 2>&1; then
    log "Formatting the new data volume (XFS)"
    "${APT[@]}" install xfsprogs
    mkfs.xfs -L esdata "$DEVICE"
  fi
  if ! grep -q ' /var/lib/elasticsearch ' /etc/fstab; then
    echo "UUID=$(blkid -s UUID -o value "$DEVICE") /var/lib/elasticsearch xfs defaults,noatime,nofail 0 2" >>/etc/fstab
  fi
  mountpoint -q /var/lib/elasticsearch || mount /var/lib/elasticsearch
  chown elasticsearch:elasticsearch /var/lib/elasticsearch
  chmod 750 /var/lib/elasticsearch
fi

# The package auto-generates its own CA, certificates and passwords at install
# time. Replace them with a plain self-signed key pair for this node: it's only
# there because transport TLS can't be switched off; verification_mode: none
# below means no node ever checks it.
log "Generating this node's self-signed transport certificate"
rm -rf "$ES_CONF/certs"
mkdir -p "$ES_CONF/certs"
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
  -keyout "$ES_CONF/certs/node.key" -out "$ES_CONF/certs/node.crt" \
  -days 36500 -subj "/CN=$NODE_NAME" 2>/dev/null
chown -R root:elasticsearch "$ES_CONF/certs"
chmod 750 "$ES_CONF/certs"
chmod 640 "$ES_CONF/certs"/*

KEYSTORE=/usr/share/elasticsearch/bin/elasticsearch-keystore
[[ -f $ES_CONF/elasticsearch.keystore ]] || "$KEYSTORE" create
for key in $("$KEYSTORE" list | grep -E '^(xpack\.security\.|autoconfiguration\.)' || true); do
  "$KEYSTORE" remove "$key"
done
# The elastic superuser's password until it's stored in the cluster (kibana.sh does that).
ELASTIC_PASSWORD=$(secret elastic_password)
printf '%s' "$ELASTIC_PASSWORD" | "$KEYSTORE" add -x -f bootstrap.password

MASTER_HOSTS=$(sed 's/ /", "/g' <<<"$MASTER_IPS")
if [[ $NODE_ROLE == master ]]; then
  ROLES='[ master ]'
  # Only for the very first start: which nodes may vote in the first election.
  # Removed again below once the cluster has formed.
  INITIAL_MASTERS='cluster.initial_master_nodes: [ "es-master-1", "es-master-2", "es-master-3" ] # bootstrap-only'
else
  ROLES='[ data, ingest ]'
  INITIAL_MASTERS=""
fi

log "Writing $ES_CONF/elasticsearch.yml"
cat >"$ES_CONF/elasticsearch.yml" <<EOF
# Written by elasticsearch.sh at first boot.
cluster.name: $CLUSTER_NAME
node.name: $NODE_NAME
node.roles: $ROLES

# Shard allocation awareness: a primary and its replica are never placed in the
# same AZ, so losing one AZ loses no data.
node.attr.zone: $AZ
cluster.routing.allocation.awareness.attributes: zone

path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch

network.bind_host: 0.0.0.0
network.publish_host: $MY_IP
http.port: 9200
transport.port: 9300

discovery.seed_hosts: [ "$MASTER_HOSTS" ]
$INITIAL_MASTERS

xpack.security.enabled: true
xpack.security.enrollment.enabled: false

# Node-to-node transport (port 9300). "enabled: true" is mandatory while login is
# on; verification_mode: none means certificates are never checked, so there's
# no CA and nothing to manage. Who may join the cluster is decided only by the
# security group: port 9300 is open to the Elasticsearch nodes themselves.
xpack.security.transport.ssl.enabled: true
xpack.security.transport.ssl.verification_mode: none
xpack.security.transport.ssl.key: certs/node.key
xpack.security.transport.ssl.certificate: certs/node.crt

# REST API (port 9200): plain HTTP. Login (username/password or API key) is
# still required; only the encryption is off.
xpack.security.http.ssl.enabled: false

# Snapshots to S3 use the instance's IAM role.
s3.client.default.endpoint: s3.$AWS_REGION.amazonaws.com
EOF
chown root:elasticsearch "$ES_CONF/elasticsearch.yml"
chmod 660 "$ES_CONF/elasticsearch.yml"

# JVM heap: fixed per role (master_heap_size / data_heap_size in Terraform).
# -Xms = -Xmx so the heap never resizes at runtime. Files in jvm.options.d/
# survive package upgrades; never edit the packaged jvm.options itself.
log "Setting JVM heap to $HEAP_SIZE"
cat >"$ES_CONF/jvm.options.d/heap.options" <<EOF
# Written by elasticsearch.sh at first boot.
-Xms$HEAP_SIZE
-Xmx$HEAP_SIZE
EOF
chown root:elasticsearch "$ES_CONF/jvm.options.d/heap.options"
chmod 640 "$ES_CONF/jvm.options.d/heap.options"

log "Starting Elasticsearch"
systemctl daemon-reload
systemctl enable elasticsearch
# --no-block: startup takes a while, and masters wait for each other.
systemctl start --no-block elasticsearch

# 200 once this node has joined a cluster with an elected master.
log "Waiting for the cluster"
for attempt in {1..120}; do
  es_api GET /_cluster/health >/dev/null 2>&1 && break
  ((attempt == 120)) && die "Elasticsearch did not join a cluster; see /var/log/elasticsearch/"
  sleep 10
done
log "Joined: $(es_api GET '/_cat/health?h=cluster,status,node.total')"

if [[ $NODE_ROLE == master ]]; then
  # Leaving initial_master_nodes in place could let a wiped node bootstrap a
  # second, empty cluster later. Elasticsearch reads the file only at startup.
  sed -i '/# bootstrap-only$/d' "$ES_CONF/elasticsearch.yml"
fi

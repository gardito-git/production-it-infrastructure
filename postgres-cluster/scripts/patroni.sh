#!/bin/bash
# Configures and starts Patroni. The first node to grab the leader lock in etcd
# runs initdb and becomes the primary; the others clone it with pg_basebackup
# and stream from it as replicas. If the primary dies, a replica takes over.
source /opt/pg-bootstrap/lib.sh

read -ra IPS <<<"$NODE_IPS"
MY_IP=$(imds local-ipv4)

ETCD_HOSTS=""
for ip in "${IPS[@]}"; do
  ETCD_HOSTS+="${ETCD_HOSTS:+,}$ip:2379"
done

log "Reading passwords from Secrets Manager"
SUPERUSER_PASSWORD=$(secret superuser_password)
REPLICATION_PASSWORD=$(secret replication_password)
PATRONI_API_PASSWORD=$(secret patroni_api_password)

# Memory settings from the instance's RAM (all nodes are the same size):
# shared_buffers 25%, effective_cache_size 75%, maintenance_work_mem 5% (max 2 GB).
MEM_MB=$(($(awk '/MemTotal/ {print $2}' /proc/meminfo) / 1024))
SHARED_BUFFERS_MB=$((MEM_MB / 4))
EFFECTIVE_CACHE_MB=$((MEM_MB * 3 / 4))
MAINTENANCE_MB=$((MEM_MB / 20 > 2048 ? 2048 : MEM_MB / 20))

mkdir -p /etc/patroni
cat >/etc/patroni/config.yml <<EOF
scope: $CLUSTER_NAME
namespace: /service/
name: pg-$((NODE_INDEX + 1))

restapi:
  listen: 0.0.0.0:8008
  connect_address: $MY_IP:8008
  # Reads (GET /primary, /replica, /health) are open, which the load balancer
  # health checks rely on. Changes (switchover, restart) need this login.
  authentication:
    username: patroni
    password: $PATRONI_API_PASSWORD

etcd3:
  hosts: $ETCD_HOSTS

bootstrap:
  # Stored in etcd at first start and shared by all nodes.
  # Change later with: patronictl -c /etc/patroni/config.yml edit-config
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    # A replica more than 1 MB behind is never promoted (limits data loss).
    maximum_lag_on_failover: 1048576
    postgresql:
      use_pg_rewind: true
      use_slots: true
      parameters:
        max_connections: 200
        shared_buffers: ${SHARED_BUFFERS_MB}MB
        effective_cache_size: ${EFFECTIVE_CACHE_MB}MB
        maintenance_work_mem: ${MAINTENANCE_MB}MB
        wal_level: replica
        wal_log_hints: "on"
        hot_standby: "on"
        max_wal_senders: 10
        max_replication_slots: 10
        wal_keep_size: 1GB
        archive_mode: "on"
        archive_timeout: 5min
        archive_command: "pgbackrest --stanza=main archive-push %p"
        password_encryption: scram-sha-256
        random_page_cost: 1.1
        effective_io_concurrency: 200
  initdb:
    - encoding: UTF8
    - locale: C.UTF-8
    - data-checksums

postgresql:
  listen: 0.0.0.0:5432
  connect_address: $MY_IP:5432
  data_dir: $PG_DATA
  bin_dir: $PG_BIN
  pgpass: /var/lib/postgresql/.pgpass_patroni
  authentication:
    superuser:
      username: postgres
      password: $SUPERUSER_PASSWORD
    replication:
      username: replicator
      password: $REPLICATION_PASSWORD
  parameters:
    unix_socket_directories: /var/run/postgresql
  # Lets a replica that fell too far behind catch up from the WAL archive in S3.
  recovery_conf:
    restore_command: 'pgbackrest --stanza=main archive-get %f "%p"'
  pg_hba:
    - local all all peer
    - host replication replicator $VPC_CIDR scram-sha-256
    - host all all $VPC_CIDR scram-sha-256
  create_replica_methods:
    - basebackup
  basebackup:
    - checkpoint: fast

watchdog:
  mode: automatic
  device: /dev/watchdog
  safety_margin: 5

tags:
  nofailover: false
  noloadbalance: false
  clonefrom: false
  nosync: false
EOF
chown -R postgres:postgres /etc/patroni
chmod 600 /etc/patroni/config.yml

# Our own unit instead of the packaged one, so the config path and
# start order (after etcd) are explicit.
cat >/etc/systemd/system/patroni.service <<'EOF'
[Unit]
Description=Patroni PostgreSQL high-availability manager
After=network-online.target etcd.service
Wants=network-online.target

[Service]
Type=simple
User=postgres
Group=postgres
ExecStart=/usr/bin/patroni /etc/patroni/config.yml
ExecReload=/bin/kill -HUP $MAINPID
# Only stop Patroni itself; it shuts PostgreSQL down cleanly on its own.
KillMode=process
TimeoutSec=30
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

log "Starting Patroni"
systemctl daemon-reload
systemctl enable --now patroni

# /health answers 200 once PostgreSQL is running on this node (primary or replica).
# Replicas copy the whole database first, so allow plenty of time.
log "Waiting for PostgreSQL to start"
wait_http http://127.0.0.1:8008/health 3600 || die "PostgreSQL did not start; see: journalctl -u patroni"

ROLE=replica
curl -sf -o /dev/null http://127.0.0.1:8008/primary && ROLE=primary
log "PostgreSQL is running as $ROLE"

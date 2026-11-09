#!/bin/bash
# Configures and starts Redis and Sentinel on this node.
#
# Every node runs both:
#   redis-server  :6379   redis-1 starts as the master, redis-2/3 as its replicas
#   redis-sentinel :26379  the 3 sentinels watch the master; if 2 of them (quorum)
#                          agree it's down, they promote a replica and repoint the rest
# After a failover the sentinels rewrite both config files, so the "redis-1 is
# master" setting below only matters for the very first start.
source /opt/redis-bootstrap/lib.sh

read -ra IPS <<<"$NODE_IPS"
MY_IP=$(imds local-ipv4)
INITIAL_MASTER=${IPS[0]}

log "Reading the password from Secrets Manager"
PASSWORD=$(secret password)

# Leave ~30% of RAM free: a background save forks Redis, and pages that change
# during the save are copied, so memory use can briefly grow.
MEM_MB=$(($(awk '/MemTotal/ {print $2}' /proc/meminfo) / 1024))
MAXMEMORY_MB=$((MEM_MB * 70 / 100))

REPLICAOF=""
if [[ $MY_IP != "$INITIAL_MASTER" ]]; then
  REPLICAOF="replicaof $INITIAL_MASTER 6379"
fi

log "Writing /etc/redis/redis.conf (maxmemory ${MAXMEMORY_MB}mb)"
cat >/etc/redis/redis.conf <<EOF
# Written by redis.sh at first boot. Sentinel may rewrite parts of it (replicaof).
bind 0.0.0.0
port 6379
protected-mode no
requirepass $PASSWORD
# Replicas log in to the master with the same password.
masterauth $PASSWORD
$REPLICAOF


daemonize no
dir /var/lib/redis
logfile ""

maxmemory ${MAXMEMORY_MB}mb
maxmemory-policy $MAXMEMORY_POLICY

# Persistence: RDB snapshots plus an append-only file (AOF) flushed every second,
# so a restart loses at most ~1 second of writes.
save 3600 1 300 100 60 10000
appendonly yes
appendfsync everysec

# Replicas serve reads but refuse writes.
replica-read-only yes
# The master stops accepting writes if it can't reach at least 1 replica
# (lag under 10 s), limiting data loss if it gets cut off from the others.
min-replicas-to-write 1
min-replicas-max-lag 10

tcp-keepalive 60
EOF

log "Writing /etc/redis/sentinel.conf"
cat >/etc/redis/sentinel.conf <<EOF
# Written by redis.sh at first boot. Sentinel rewrites this file as it learns
# about other sentinels, replicas and failovers; don't edit it while running.
port 26379
bind 0.0.0.0
protected-mode no
daemonize no
dir /var/lib/redis
logfile ""

# Sentinel itself needs the password, and uses it with the other sentinels.
requirepass $PASSWORD
sentinel sentinel-pass $PASSWORD

# Announce the private IP so clients and other sentinels get a reachable address.
sentinel announce-ip $MY_IP

sentinel monitor $SENTINEL_MASTER_NAME $INITIAL_MASTER 6379 2
sentinel auth-pass $SENTINEL_MASTER_NAME $PASSWORD
# The master is considered down after 5 s without a reply.
sentinel down-after-milliseconds $SENTINEL_MASTER_NAME 5000
sentinel failover-timeout $SENTINEL_MASTER_NAME 60000
# Re-sync replicas to a new master one at a time.
sentinel parallel-syncs $SENTINEL_MASTER_NAME 1
EOF

# Both files hold the password. Redis/Sentinel rewrite them through a temporary
# file in /etc/redis, so the redis user needs the directory too.
chown redis:redis /etc/redis /etc/redis/redis.conf /etc/redis/sentinel.conf
chmod 750 /etc/redis
chmod 640 /etc/redis/redis.conf /etc/redis/sentinel.conf

# Our own units instead of the packaged ones, so the commands and start order are explicit.
cat >/etc/systemd/system/redis-server.service <<'EOF'
[Unit]
Description=Redis server
After=network-online.target disable-thp.service
Wants=network-online.target

[Service]
Type=simple
User=redis
Group=redis
ExecStart=/usr/bin/redis-server /etc/redis/redis.conf
TimeoutStartSec=300
TimeoutStopSec=60
Restart=always
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

cat >/etc/systemd/system/redis-sentinel.service <<'EOF'
[Unit]
Description=Redis Sentinel
After=network-online.target redis-server.service
Wants=network-online.target

[Service]
Type=simple
User=redis
Group=redis
ExecStart=/usr/bin/redis-server /etc/redis/sentinel.conf --sentinel
Restart=always
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

log "Starting Redis and Sentinel"
systemctl daemon-reload
systemctl enable redis-server redis-sentinel
systemctl restart redis-server
systemctl restart redis-sentinel

export REDISCLI_AUTH=$PASSWORD
for attempt in {1..60}; do
  redis-cli -h 127.0.0.1 ping 2>/dev/null | grep -q PONG && break
  ((attempt == 60)) && die "Redis did not start; see: journalctl -u redis-server"
  sleep 2
done
log "Redis role: $(redis-cli -h 127.0.0.1 role 2>/dev/null | head -n1)"

log "Scheduling daily RDB backups to s3://$BACKUP_BUCKET/$BACKUP_PREFIX/ (master only)"
cat >/etc/systemd/system/redis-backup.service <<EOF
[Unit]
Description=Upload a Redis RDB snapshot to S3 (only on the current master)

[Service]
Type=oneshot
ExecStart=$SCRIPT_DIR/redis-backup.sh
EOF

cat >/etc/systemd/system/redis-backup.timer <<'EOF'
[Unit]
Description=Daily Redis backup

[Timer]
OnCalendar=*-*-* 02:00:00 UTC
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now redis-backup.timer
log "Redis node ready"

#!/bin/bash
# Configures RabbitMQ on this node and joins (or forms) the cluster.
#
#   rabbitmq-1 starts first and forms the cluster; rabbitmq-2/3 wait for it,
#   then find it through peer discovery (classic_config) and join.
#   All three must share the same Erlang cookie (from Secrets Manager).
#
# Messages survive restarts because they're on disk: durable queues and
# persistent messages are written to /var/lib/rabbitmq. Quorum queues (the
# default for new queues, set below) also copy every message to all 3 nodes.
source /opt/rabbitmq-bootstrap/lib.sh

read -ra IPS <<<"$NODE_IPS"
CONF=/etc/rabbitmq
RABBITMQ_HOME=/var/lib/rabbitmq

log "Reading the Erlang cookie and admin password from Secrets Manager"
COOKIE=$(secret erlang_cookie)
ADMIN_PASSWORD=$(secret password)

# The installer was told not to start RabbitMQ (node-prep.sh); make sure no
# database from a stray start exists, so the node starts clean under its real name.
systemctl stop rabbitmq-server 2>/dev/null || true
rm -rf "${RABBITMQ_HOME:?}/mnesia"

# The cookie is the nodes' shared secret: same on all, readable only by rabbitmq.
install -o rabbitmq -g rabbitmq -m 600 /dev/null "$RABBITMQ_HOME/.erlang.cookie"
printf '%s' "$COOKIE" >"$RABBITMQ_HOME/.erlang.cookie"
chmod 400 "$RABBITMQ_HOME/.erlang.cookie"

cat >"$CONF/rabbitmq-env.conf" <<EOF
# Written by rabbitmq.sh at first boot. The node's identity: its data in
# $RABBITMQ_HOME/mnesia belongs to this name.
NODENAME=rabbit@$NODE_NAME
EOF

log "Writing $CONF/rabbitmq.conf"
cat >"$CONF/rabbitmq.conf" <<EOF
# Written by rabbitmq.sh at first boot. Same on every node.
cluster_name = $CLUSTER_NAME

# Peer discovery: the fixed list of nodes. A new node contacts them and joins
# whichever is running.
cluster_formation.peer_discovery_backend = classic_config
cluster_formation.classic_config.nodes.1 = rabbit@rabbitmq-1
cluster_formation.classic_config.nodes.2 = rabbit@rabbitmq-2
cluster_formation.classic_config.nodes.3 = rabbit@rabbitmq-3
cluster_formation.target_cluster_size_hint = 3

# AMQP for apps (plain, login required), management UI, Prometheus metrics.
listeners.tcp.default = 5672
management.tcp.port = 15672
prometheus.tcp.port = 15692

# Created when the cluster is first formed. Apps should get their own users
# (see README), not admin. No "guest" user is created.
default_user = admin
default_pass = $ADMIN_PASSWORD
default_user_tags.administrator = true
default_permissions.configure = .*
default_permissions.read = .*
default_permissions.write = .*

# Flow control. Above 60% of RAM, or below 5 GB free disk, RabbitMQ blocks
# publishers until consumers catch up, instead of crashing or filling the disk.
vm_memory_high_watermark.relative = 0.6
disk_free_limit.absolute = 5GB

# Spread quorum queue leaders evenly over the 3 nodes.
queue_leader_locator = balanced
EOF
# The file holds the admin password.
chown root:rabbitmq "$CONF/rabbitmq.conf" "$CONF/rabbitmq-env.conf"
chmod 640 "$CONF/rabbitmq.conf" "$CONF/rabbitmq-env.conf"

echo '[rabbitmq_management,rabbitmq_prometheus].' >"$CONF/enabled_plugins"
chown root:rabbitmq "$CONF/enabled_plugins"
chmod 644 "$CONF/enabled_plugins"

# Every client connection and queue file uses a file descriptor.
mkdir -p /etc/systemd/system/rabbitmq-server.service.d
cat >/etc/systemd/system/rabbitmq-server.service.d/limits.conf <<'EOF'
[Service]
LimitNOFILE=65536
EOF
systemctl daemon-reload
systemctl enable rabbitmq-server

# rabbitmq-1 forms the cluster. The others wait until it's up, so all three
# don't start at once and form separate one-node clusters. If rabbitmq-1 is
# down for good (e.g. this node is a replacement), start anyway: peer discovery
# then joins whichever node is running.
if ((NODE_INDEX > 0)); then
  log "Waiting for rabbitmq-1 (${IPS[0]}:5672)"
  for _ in {1..90}; do
    timeout 3 bash -c "</dev/tcp/${IPS[0]}/5672" 2>/dev/null && break
    sleep 10
  done
fi

log "Starting RabbitMQ"
systemctl start rabbitmq-server
# await_startup waits for a node that is booting, but fails at once if the
# Erlang VM isn't up yet, so retry it for up to ~10 minutes.
for attempt in {1..60}; do
  rabbitmqctl -q await_startup --timeout 30 >/dev/null 2>&1 && break
  ((attempt == 60)) && die "RabbitMQ did not start; see /var/log/rabbitmq/"
  sleep 10
done

if ((NODE_INDEX == 0)); then
  # New queues on the default vhost are quorum queues unless an app asks for
  # another type: replicated to all 3 nodes, on disk, survive losing a node.
  log "Making quorum the default queue type on vhost /"
  rabbitmqctl update_vhost_metadata / --default-queue-type quorum
fi

RUNNING=$(rabbitmqctl cluster_status --formatter json | jq -r '.running_nodes | join(", ")')
log "Cluster running nodes: $RUNNING"

log "Scheduling daily definitions backups to s3://$BACKUP_BUCKET/$BACKUP_PREFIX/"
cat >/etc/systemd/system/rabbitmq-backup.service <<EOF
[Unit]
Description=Upload RabbitMQ definitions (users, vhosts, queues, policies) to S3

[Service]
Type=oneshot
ExecStart=$SCRIPT_DIR/rabbitmq-backup.sh
EOF

cat >/etc/systemd/system/rabbitmq-backup.timer <<'EOF'
[Unit]
Description=Daily RabbitMQ definitions backup

[Timer]
OnCalendar=*-*-* 02:30:00 UTC
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now rabbitmq-backup.timer
log "RabbitMQ node ready"

#!/bin/bash
# Starts this node's etcd member. The 3 etcd members only store Patroni's
# leader lock and cluster state; Patroni needs a majority (2 of 3) to elect a primary.
source /opt/pg-bootstrap/lib.sh

read -ra IPS <<<"$NODE_IPS"
MY_IP=$(imds local-ipv4)

INITIAL_CLUSTER=""
for i in "${!IPS[@]}"; do
  INITIAL_CLUSTER+="${INITIAL_CLUSTER:+,}pg-$((i + 1))=http://${IPS[$i]}:2380"
done

id etcd >/dev/null 2>&1 || useradd --system --home-dir /var/lib/etcd --shell /usr/sbin/nologin etcd
mkdir -p /var/lib/etcd
chown etcd:etcd /var/lib/etcd
chmod 700 /var/lib/etcd

# Plain HTTP: only the postgres security group can reach ports 2379-2380.
# See the README's TO-DO list for TLS.
cat >/etc/systemd/system/etcd.service <<EOF
[Unit]
Description=etcd for Patroni
After=network-online.target
Wants=network-online.target

[Service]
User=etcd
Type=notify
ExecStart=/usr/local/bin/etcd \\
  --name pg-$((NODE_INDEX + 1)) \\
  --data-dir /var/lib/etcd \\
  --listen-peer-urls http://$MY_IP:2380 \\
  --initial-advertise-peer-urls http://$MY_IP:2380 \\
  --listen-client-urls http://$MY_IP:2379,http://127.0.0.1:2379 \\
  --advertise-client-urls http://$MY_IP:2379 \\
  --initial-cluster $INITIAL_CLUSTER \\
  --initial-cluster-token $CLUSTER_NAME \\
  --initial-cluster-state new
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

log "Starting etcd"
systemctl daemon-reload
# --no-block: with Type=notify, start only returns once a quorum exists,
# which needs the other nodes; don't hang here waiting for them.
systemctl enable --now --no-block etcd

log "Waiting for etcd quorum"
for _ in {1..180}; do
  if etcdctl --endpoints=http://127.0.0.1:2379 endpoint health >/dev/null 2>&1; then
    log "etcd is healthy"
    exit 0
  fi
  sleep 5
done
die "etcd did not become healthy; check the other nodes"

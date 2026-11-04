#!/bin/bash
# Runs on every etcd node. Installs this member's certificates (etcd-2 and
# etcd-3 download them from S3) and starts etcd as a kubelet static pod.
source /opt/k8s-bootstrap/lib.sh

MY_IP=$(imds local-ipv4)

if [[ ! -f /etc/kubernetes/etcd-kubeadmcfg.yaml ]]; then
  s3_wait "etcd/$MY_IP.tar.gz" /root/etcd-bundle.tar.gz
  mkdir -p /root/etcd-bundle /etc/kubernetes
  tar -xzf /root/etcd-bundle.tar.gz -C /root/etcd-bundle
  cp -R /root/etcd-bundle/pki /etc/kubernetes/
  cp /root/etcd-bundle/kubeadmcfg.yaml /etc/kubernetes/etcd-kubeadmcfg.yaml
  rm -rf /root/etcd-bundle /root/etcd-bundle.tar.gz
fi
chmod -R go-rwx /etc/kubernetes/pki

log "Writing the etcd static pod manifest"
kubeadm init phase etcd local --config=/etc/kubernetes/etcd-kubeadmcfg.yaml

# etcd only reports healthy once a quorum (2 of 3) of members is up.
wait_tcp "$MY_IP" 2379
log "etcd is listening on $MY_IP:2379"

log "Scheduling etcd snapshots to s3://$BACKUP_BUCKET/$BACKUP_PREFIX/etcd/ ($ETCD_BACKUP_SCHEDULE)"
cat >/etc/systemd/system/etcd-backup.service <<EOF
[Unit]
Description=Snapshot etcd and upload it to S3

[Service]
Type=oneshot
ExecStart=$SCRIPT_DIR/etcd-backup.sh
EOF

cat >/etc/systemd/system/etcd-backup.timer <<EOF
[Unit]
Description=Scheduled etcd snapshots

[Timer]
OnCalendar=$ETCD_BACKUP_SCHEDULE
# Spread the 3 members' uploads a little, and catch up after downtime.
RandomizedDelaySec=10min
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now etcd-backup.timer

#!/bin/bash
# Run by etcd-backup.timer on every etcd node (set up by etcd-start.sh).
# Snapshots this member's etcd and uploads it to
#   s3://$BACKUP_BUCKET/$BACKUP_PREFIX/etcd/etcd-N/etcd-N-<timestamp>.db.gz
# Every member uploads its own copy, so backups keep running while any member is alive.
source /opt/k8s-bootstrap/lib.sh

MY_IP=$(imds local-ipv4)
NODE="etcd-$((NODE_INDEX + 1))"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)

# etcd runs in a container (kubeadm static pod) with the host's /var/lib/etcd
# mounted at the same path, so a snapshot written there lands on the host.
SNAPSHOT=/var/lib/etcd/backup-$STAMP.db
trap 'rm -f "$SNAPSHOT" "$SNAPSHOT.gz"' EXIT

CONTAINER=$(crictl ps --name '^etcd$' --state running -q | head -n1)
[[ -n $CONTAINER ]] || die "the etcd container is not running"

log "Taking etcd snapshot"
crictl exec "$CONTAINER" etcdctl \
  --endpoints="https://$MY_IP:2379" \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
  --key=/etc/kubernetes/pki/etcd/healthcheck-client.key \
  snapshot save "$SNAPSHOT"
gzip "$SNAPSHOT"

KEY="$BACKUP_PREFIX/etcd/$NODE/$NODE-$STAMP.db.gz"
aws s3 cp --only-show-errors --sse AES256 "$SNAPSHOT.gz" "s3://$BACKUP_BUCKET/$KEY"
log "Uploaded s3://$BACKUP_BUCKET/$KEY"

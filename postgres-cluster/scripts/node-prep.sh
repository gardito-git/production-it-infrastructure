#!/bin/bash
# OS settings, the data volume, and the software: PostgreSQL, Patroni,
# pgBackRest (all from the official PostgreSQL apt repo) and etcd.
source /opt/pg-bootstrap/lib.sh

# Ubuntu's AWS images ship the SSM agent. Access is SSH over the VPN instead.
if snap list amazon-ssm-agent >/dev/null 2>&1; then
  log "Removing the AWS SSM agent"
  snap remove amazon-ssm-agent
fi

log "Kernel settings for a database server"
cat >/etc/sysctl.d/99-postgres.conf <<'EOF'
# Keep PostgreSQL's memory in RAM; swap only as a last resort.
vm.swappiness = 1
# Flush dirty pages early and steadily instead of in big write bursts.
vm.dirty_background_ratio = 5
vm.dirty_ratio = 10
EOF
sysctl --system >/dev/null

log "Installing base tools"
"${APT[@]}" update
"${APT[@]}" install ca-certificates curl gnupg jq xfsprogs
if ! command -v aws >/dev/null; then
  snap install aws-cli --classic
fi

# The data volume is a separate EBS volume, so it can be sized independently
# and survives instance replacement. On Nitro instances it shows up as an NVMe
# device whose serial is the volume ID without the dash.
DEVICE=/dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_${DATA_VOLUME_ID/-/}
log "Waiting for data volume $DATA_VOLUME_ID"
for _ in {1..120}; do
  [[ -e $DEVICE ]] && break
  sleep 5
done
[[ -e $DEVICE ]] || die "data volume $DATA_VOLUME_ID never appeared at $DEVICE"

if ! blkid "$DEVICE" >/dev/null 2>&1; then
  log "Formatting the new data volume (XFS)"
  mkfs.xfs -L pgdata "$DEVICE"
fi
mkdir -p /data
if ! grep -q ' /data ' /etc/fstab; then
  echo "UUID=$(blkid -s UUID -o value "$DEVICE") /data xfs defaults,noatime,nofail 0 2" >>/etc/fstab
fi
mountpoint -q /data || mount /data

log "Installing PostgreSQL $PG_VERSION, Patroni and pgBackRest"
mkdir -p /etc/apt/keyrings /etc/postgresql-common
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc |
  gpg --dearmor --yes -o /etc/apt/keyrings/pgdg.gpg
echo "deb [signed-by=/etc/apt/keyrings/pgdg.gpg] https://apt.postgresql.org/pub/repos/apt noble-pgdg main" \
  >/etc/apt/sources.list.d/pgdg.list
# Patroni creates and manages the database itself; stop Ubuntu creating a default one.
echo "create_main_cluster = false" >/etc/postgresql-common/createcluster.conf
"${APT[@]}" update
"${APT[@]}" install "postgresql-$PG_VERSION" patroni pgbackrest
# Patroni starts PostgreSQL, so the packaged service must never start it too.
systemctl disable --now postgresql

mkdir -p "$PG_DATA"
chown -R postgres:postgres /data/postgresql
chmod 700 "$PG_DATA"

log "Installing etcd v$ETCD_VERSION"
cd /tmp
ETCD_TAR="etcd-v$ETCD_VERSION-linux-amd64.tar.gz"
curl -fsSLO "https://github.com/etcd-io/etcd/releases/download/v$ETCD_VERSION/$ETCD_TAR"
curl -fsSL "https://github.com/etcd-io/etcd/releases/download/v$ETCD_VERSION/SHA256SUMS" |
  grep " $ETCD_TAR\$" | sha256sum --check
tar -xzf "$ETCD_TAR" --strip-components=1 -C /usr/local/bin \
  "etcd-v$ETCD_VERSION-linux-amd64/etcd" "etcd-v$ETCD_VERSION-linux-amd64/etcdctl"
rm -f "$ETCD_TAR"

# Patroni's watchdog reboots a primary that stops responding, so a frozen node
# can't keep accepting writes after a new primary has been elected.
log "Enabling the softdog watchdog for Patroni"
echo softdog >/etc/modules-load.d/softdog.conf
modprobe softdog || log "softdog module not available; Patroni will run without a watchdog"
echo 'KERNEL=="watchdog", OWNER="postgres", GROUP="postgres", MODE="0600"' \
  >/etc/udev/rules.d/99-watchdog.rules
[[ -e /dev/watchdog ]] && chown postgres:postgres /dev/watchdog

log "Node prep finished"

#!/bin/bash
# OS settings MongoDB 8.0 recommends, MongoDB from repo.mongodb.org, and the
# data volume at /var/lib/mongodb.
source /opt/mongodb-bootstrap/lib.sh

# Ubuntu's AWS images ship the SSM agent. Access is SSH over the VPN instead.
if snap list amazon-ssm-agent >/dev/null 2>&1; then
  log "Removing the AWS SSM agent"
  snap remove amazon-ssm-agent
fi

log "Kernel settings for MongoDB"
cat >/etc/sysctl.d/99-mongodb.conf <<'EOF'
# Keep MongoDB in RAM; swap only as a last resort.
vm.swappiness = 1
# Memory-mapped files and many connections.
vm.max_map_count = 262144
# Notice dead client connections after 2 minutes instead of 2 hours.
net.ipv4.tcp_keepalive_time = 120
EOF
sysctl --system >/dev/null

# MongoDB 8.0's memory allocator (TCMalloc) wants transparent huge pages ON,
# the opposite of older versions. They must be set before mongod starts.
cat >/etc/systemd/system/mongodb-thp.service <<'EOF'
[Unit]
Description=Transparent huge page settings for MongoDB 8.0
Before=mongod.service

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo always >/sys/kernel/mm/transparent_hugepage/enabled && echo defer+madvise >/sys/kernel/mm/transparent_hugepage/defrag && echo 0 >/sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_none && echo 1 >/proc/sys/vm/overcommit_memory'

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now mongodb-thp.service

log "Installing base tools"
"${APT[@]}" update
"${APT[@]}" install ca-certificates curl gnupg jq xfsprogs
if ! command -v aws >/dev/null; then
  snap install aws-cli --classic
fi

log "Installing MongoDB $MONGODB_VERSION"
curl -fsSL "https://pgp.mongodb.com/server-$MONGODB_VERSION.asc" |
  gpg --dearmor --yes -o "/usr/share/keyrings/mongodb-server-$MONGODB_VERSION.gpg"
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/mongodb-server-$MONGODB_VERSION.gpg] https://repo.mongodb.org/apt/ubuntu noble/mongodb-org/$MONGODB_VERSION multiverse" \
  >/etc/apt/sources.list.d/mongodb-org.list
# Pin the release series, so new nodes get the same MongoDB as the running ones.
cat >/etc/apt/preferences.d/mongodb <<EOF
Package: mongodb-org*
Pin: version $MONGODB_VERSION.*
Pin-Priority: 1001
EOF
"${APT[@]}" update
# mongodb-org = server + mongos + mongosh + database tools (mongodump, mongorestore).
"${APT[@]}" install mongodb-org
# Upgraded deliberately, one member at a time; never by apt upgrade.
mapfile -t HOLD < <(dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' 'mongodb-org*' | awk '$1 == "ii" {print $2}')
apt-mark hold "${HOLD[@]}" >/dev/null
systemctl stop mongod 2>/dev/null || true
log "Installed $(dpkg-query -W -f='${Package} ${Version}' mongodb-org-server)"

# The data volume is a separate EBS volume. On Nitro instances it's an NVMe
# device whose serial is the volume ID without the dash.
DEVICE=/dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_${DATA_VOLUME_ID/-/}
log "Waiting for data volume $DATA_VOLUME_ID"
for _ in {1..120}; do
  [[ -e $DEVICE ]] && break
  sleep 5
done
[[ -e $DEVICE ]] || die "data volume $DATA_VOLUME_ID never appeared at $DEVICE"

# XFS is what MongoDB recommends for WiredTiger.
if ! blkid "$DEVICE" >/dev/null 2>&1; then
  log "Formatting the new data volume (XFS)"
  mkfs.xfs -L mongodata "$DEVICE"
fi
if ! grep -q ' /var/lib/mongodb ' /etc/fstab; then
  echo "UUID=$(blkid -s UUID -o value "$DEVICE") /var/lib/mongodb xfs defaults,noatime,nofail 0 2" >>/etc/fstab
fi
mkdir -p /var/lib/mongodb
mountpoint -q /var/lib/mongodb || mount /var/lib/mongodb
chown mongodb:mongodb /var/lib/mongodb
chmod 750 /var/lib/mongodb

log "Node prep finished"

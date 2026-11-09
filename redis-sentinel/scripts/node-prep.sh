#!/bin/bash
# OS settings Redis recommends, the data volume, and Redis itself from the
# official packages.redis.io repository.
source /opt/redis-bootstrap/lib.sh

# Ubuntu's AWS images ship the SSM agent. Access is SSH over the VPN instead.
if snap list amazon-ssm-agent >/dev/null 2>&1; then
  log "Removing the AWS SSM agent"
  snap remove amazon-ssm-agent
fi

log "Kernel settings for Redis"
cat >/etc/sysctl.d/99-redis.conf <<'EOF'
# Lets the background save (fork) succeed even when memory looks tight.
vm.overcommit_memory = 1
# Keep Redis in RAM; swap only as a last resort.
vm.swappiness = 1
# Room for bursts of new client connections.
net.core.somaxconn = 1024
EOF
sysctl --system >/dev/null

# Transparent huge pages cause latency spikes and memory bloat after fork.
cat >/etc/systemd/system/disable-thp.service <<'EOF'
[Unit]
Description=Disable transparent huge pages (for Redis)
Before=redis-server.service

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo never > /sys/kernel/mm/transparent_hugepage/enabled'

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now disable-thp.service

log "Installing base tools"
"${APT[@]}" update
"${APT[@]}" install ca-certificates curl gnupg jq xfsprogs
if ! command -v aws >/dev/null; then
  snap install aws-cli --classic
fi

log "Installing Redis $REDIS_VERSION"
mkdir -p /etc/apt/keyrings
curl -fsSL https://packages.redis.io/gpg | gpg --dearmor --yes -o /etc/apt/keyrings/redis.gpg
echo "deb [signed-by=/etc/apt/keyrings/redis.gpg] https://packages.redis.io/deb noble main" \
  >/etc/apt/sources.list.d/redis.list
# Pin the minor version, so new nodes get the same Redis as the running ones.
cat >/etc/apt/preferences.d/redis <<EOF
Package: redis redis-server redis-sentinel redis-tools
Pin: version 6:$REDIS_VERSION.*
Pin-Priority: 1001
EOF
"${APT[@]}" update
"${APT[@]}" install redis-server redis-sentinel redis-tools
apt-mark hold redis-server redis-sentinel redis-tools
# The packages start Redis with their default config; redis.sh replaces it.
systemctl stop redis-server redis-sentinel || true

# The data volume (RDB snapshots + AOF) is a separate EBS volume. On Nitro
# instances it's an NVMe device whose serial is the volume ID without the dash.
DEVICE=/dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_${DATA_VOLUME_ID/-/}
log "Waiting for data volume $DATA_VOLUME_ID"
for _ in {1..120}; do
  [[ -e $DEVICE ]] && break
  sleep 5
done
[[ -e $DEVICE ]] || die "data volume $DATA_VOLUME_ID never appeared at $DEVICE"

if ! blkid "$DEVICE" >/dev/null 2>&1; then
  log "Formatting the new data volume (XFS)"
  mkfs.xfs -L redisdata "$DEVICE"
fi
if ! grep -q ' /var/lib/redis ' /etc/fstab; then
  echo "UUID=$(blkid -s UUID -o value "$DEVICE") /var/lib/redis xfs defaults,noatime,nofail 0 2" >>/etc/fstab
fi
mkdir -p /var/lib/redis
mountpoint -q /var/lib/redis || mount /var/lib/redis
chown redis:redis /var/lib/redis
chmod 750 /var/lib/redis

log "Node prep finished"

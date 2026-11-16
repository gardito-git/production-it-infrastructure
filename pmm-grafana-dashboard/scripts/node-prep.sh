#!/bin/bash
# Docker and the data volume at /data.
source /opt/monitoring-bootstrap/lib.sh

# Ubuntu's AWS images ship the SSM agent. Access is SSH over the VPN instead.
if snap list amazon-ssm-agent >/dev/null 2>&1; then
  log "Removing the AWS SSM agent"
  snap remove amazon-ssm-agent
fi

log "Installing base tools"
"${APT[@]}" update
"${APT[@]}" install ca-certificates curl gnupg jq xfsprogs python3
if ! command -v aws >/dev/null; then
  snap install aws-cli --classic
fi

log "Installing Docker"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable" \
  >/etc/apt/sources.list.d/docker.list
"${APT[@]}" update
"${APT[@]}" install docker-ce docker-ce-cli containerd.io
systemctl enable --now docker

# All monitoring data lives on a separate EBS volume. On Nitro instances it's an
# NVMe device whose serial is the volume ID without the dash.
DEVICE=/dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_${DATA_VOLUME_ID/-/}
log "Waiting for data volume $DATA_VOLUME_ID"
for _ in {1..120}; do
  [[ -e $DEVICE ]] && break
  sleep 5
done
[[ -e $DEVICE ]] || die "data volume $DATA_VOLUME_ID never appeared at $DEVICE"

if ! blkid "$DEVICE" >/dev/null 2>&1; then
  log "Formatting the new data volume (XFS)"
  mkfs.xfs -L monitoring "$DEVICE"
fi
if ! grep -q " $DATA_DIR " /etc/fstab; then
  echo "UUID=$(blkid -s UUID -o value "$DEVICE") $DATA_DIR xfs defaults,noatime,nofail 0 2" >>/etc/fstab
fi
mkdir -p "$DATA_DIR"
mountpoint -q "$DATA_DIR" || mount "$DATA_DIR"

# One folder per container, owned by the user each image runs as.
mkdir -p "$DATA_DIR/pmm" "$DATA_DIR/loki" "$DATA_DIR/prometheus" /etc/monitoring
chown 1000:1000 "$DATA_DIR/pmm"            # PMM 3 runs as uid 1000
chown 10001:10001 "$DATA_DIR/loki"         # grafana/loki
chown 65534:65534 "$DATA_DIR/prometheus"   # prom/prometheus (nobody)

log "Node prep finished"

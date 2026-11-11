#!/bin/bash
# Base tools, Docker, Nginx, certbot, and the data volume mounted at /data.
source /opt/harbor-bootstrap/lib.sh

# Ubuntu's AWS images ship the SSM agent. Access is SSH over the VPN instead.
if snap list amazon-ssm-agent >/dev/null 2>&1; then
  log "Removing the AWS SSM agent"
  snap remove amazon-ssm-agent
fi

log "Installing base tools"
# Retry in case the network isn't usable yet at the very first boot.
for attempt in {1..30}; do
  "${APT[@]}" update && break
  log "apt-get update failed (attempt $attempt), retrying"
  sleep 10
done
"${APT[@]}" install ca-certificates curl gnupg jq xfsprogs dnsutils nginx python3-yaml
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
"${APT[@]}" install docker-ce docker-ce-cli containerd.io docker-compose-plugin
systemctl enable --now docker

log "Installing certbot"
snap install certbot --classic
ln -sf /snap/bin/certbot /usr/local/bin/certbot

# Harbor's state lives on a separate EBS volume. On Nitro instances it's an NVMe
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
  mkfs.xfs -L harbordata "$DEVICE"
fi
if ! grep -q " $DATA_DIR " /etc/fstab; then
  echo "UUID=$(blkid -s UUID -o value "$DEVICE") $DATA_DIR xfs defaults,noatime,nofail 0 2" >>/etc/fstab
fi
mkdir -p "$DATA_DIR"
mountpoint -q "$DATA_DIR" || mount "$DATA_DIR"

# The certificate lives on the data volume too: a replaced server reuses it
# instead of running into Let's Encrypt's limit on duplicate certificates.
mkdir -p "$DATA_DIR/letsencrypt" /etc/letsencrypt
if ! grep -q ' /etc/letsencrypt ' /etc/fstab; then
  echo "$DATA_DIR/letsencrypt /etc/letsencrypt none bind,nofail,x-systemd.requires-mounts-for=$DATA_DIR 0 0" >>/etc/fstab
fi
mountpoint -q /etc/letsencrypt || mount /etc/letsencrypt

log "Node prep finished"

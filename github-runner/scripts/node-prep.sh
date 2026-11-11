#!/bin/bash
# The tools every job can count on, whatever language the repository uses.
# Languages themselves (Node.js, Java, Go, Python versions...) are NOT installed
# here: workflows pick their version with actions/setup-node, setup-java,
# setup-go, setup-python..., which cache it on the runner.
source /opt/github-runner-bootstrap/lib.sh

# Ubuntu's AWS images ship the SSM agent. Access is SSH over the VPN instead.
if snap list amazon-ssm-agent >/dev/null 2>&1; then
  log "Removing the AWS SSM agent"
  snap remove amazon-ssm-agent
fi

log "Kernel settings for builds"
cat >/etc/sysctl.d/99-github-runner.conf <<'EOF'
# File watchers for JS tooling (webpack, jest, next build).
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 1024
# Use the swap file only when RAM is really short.
vm.swappiness = 10
EOF
sysctl --system >/dev/null

# 4 GiB of swap: a heavy build (next build, Maven, Gradle) that briefly needs
# more than 8 GiB slows down instead of being killed.
if [[ ! -f /swapfile ]]; then
  log "Creating a 4 GiB swap file"
  fallocate -l 4G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  echo '/swapfile none swap sw 0 0' >>/etc/fstab
  swapon /swapfile || log "swapon failed (fine inside a container)"
fi

log "Installing build tools"
"${APT[@]}" update
"${APT[@]}" install ca-certificates curl gnupg jq git git-lfs unzip zip xz-utils \
  build-essential python3 python3-venv python3-pip ansible python3-boto3 python3-botocore
if ! command -v aws >/dev/null; then
  snap install aws-cli --classic
fi

# Docker from Docker's own repository: docker build, docker compose, and
# workflows that run steps in containers (container: / services:).
log "Installing Docker"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable" \
  >/etc/apt/sources.list.d/docker.list
"${APT[@]}" update
"${APT[@]}" install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker 2>/dev/null || log "Docker service not started (fine inside a container)"

# Disk hygiene: Docker images, build cache and old workspaces pile up on a
# permanent runner. Daily, remove what no job used in the last 3 days.
cat >/usr/local/sbin/runner-cleanup <<'EOF'
#!/bin/bash
set -u
docker system prune --all --force --filter "until=72h"
docker builder prune --all --force --filter "until=72h"
docker volume prune --force
# Workspaces of repositories not built for 14 days.
find /home/runner/actions-runner/_work -mindepth 1 -maxdepth 1 -type d \
  ! -name '_*' -mtime +14 -exec rm -rf {} + 2>/dev/null
df -h /
EOF
chmod 755 /usr/local/sbin/runner-cleanup

cat >/etc/systemd/system/runner-cleanup.service <<'EOF'
[Unit]
Description=Remove old Docker images, build cache and workspaces

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/runner-cleanup
EOF

cat >/etc/systemd/system/runner-cleanup.timer <<'EOF'
[Unit]
Description=Daily runner disk cleanup

[Timer]
OnCalendar=*-*-* 03:00:00 UTC
RandomizedDelaySec=30m
Persistent=true

[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
systemctl enable --now runner-cleanup.timer 2>/dev/null || log "Timer not enabled (fine inside a container)"

log "Node prep finished"

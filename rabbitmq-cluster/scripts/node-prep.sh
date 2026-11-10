#!/bin/bash
# Hostname and name resolution for the cluster, OS settings, and RabbitMQ +
# Erlang from Team RabbitMQ's apt repositories.
source /opt/rabbitmq-bootstrap/lib.sh

# Ubuntu's AWS images ship the SSM agent. Access is SSH over the VPN instead.
if snap list amazon-ssm-agent >/dev/null 2>&1; then
  log "Removing the AWS SSM agent"
  snap remove amazon-ssm-agent
fi

# RabbitMQ node names are rabbit@<hostname>, and a node's data belongs to its
# name. So the hostname must be fixed (rabbitmq-1/2/3) and survive reboots,
# and every node must resolve the others' short names.
log "Setting hostname $NODE_NAME"
hostnamectl set-hostname "$NODE_NAME"
cat >/etc/cloud/cloud.cfg.d/99-rabbitmq-hostname.cfg <<'EOF'
# Keep the hostname RabbitMQ's node name depends on (rabbit@rabbitmq-N).
preserve_hostname: true
manage_etc_hosts: false
EOF

read -ra IPS <<<"$NODE_IPS"
sed -i '/# rabbitmq-cluster$/d' /etc/hosts
for i in "${!IPS[@]}"; do
  echo "${IPS[$i]} rabbitmq-$((i + 1)) # rabbitmq-cluster" >>/etc/hosts
done

log "Kernel settings for RabbitMQ"
cat >/etc/sysctl.d/99-rabbitmq.conf <<'EOF'
# Room for bursts of new client connections.
net.core.somaxconn = 4096
net.ipv4.tcp_max_syn_backlog = 4096
# Keep RabbitMQ in RAM; swap only as a last resort.
vm.swappiness = 1
EOF
sysctl --system >/dev/null

log "Installing base tools"
"${APT[@]}" update
"${APT[@]}" install ca-certificates curl gnupg jq
if ! command -v aws >/dev/null; then
  snap install aws-cli --classic
fi

# Team RabbitMQ's repositories: current RabbitMQ and the Erlang versions it
# needs (Ubuntu's own Erlang is too old). deb1 and deb2 are mirrors.
log "Adding Team RabbitMQ apt repositories"
curl -fsSL "https://keys.openpgp.org/vks/v1/by-fingerprint/0A9AF2115F4687BD29803A206B73A36E6026DFCA" |
  gpg --dearmor --yes -o /usr/share/keyrings/com.rabbitmq.team.gpg
cat >/etc/apt/sources.list.d/rabbitmq.list <<'EOF'
deb [arch=amd64 signed-by=/usr/share/keyrings/com.rabbitmq.team.gpg] https://deb1.rabbitmq.com/rabbitmq-erlang/ubuntu/noble noble main
deb [arch=amd64 signed-by=/usr/share/keyrings/com.rabbitmq.team.gpg] https://deb2.rabbitmq.com/rabbitmq-erlang/ubuntu/noble noble main
deb [arch=amd64 signed-by=/usr/share/keyrings/com.rabbitmq.team.gpg] https://deb1.rabbitmq.com/rabbitmq-server/ubuntu/noble noble main
deb [arch=amd64 signed-by=/usr/share/keyrings/com.rabbitmq.team.gpg] https://deb2.rabbitmq.com/rabbitmq-server/ubuntu/noble noble main
EOF
# Pin the minor version, so new nodes get the same RabbitMQ as the running ones.
cat >/etc/apt/preferences.d/rabbitmq <<EOF
Package: rabbitmq-server
Pin: version $RABBITMQ_VERSION.*
Pin-Priority: 1001
EOF
"${APT[@]}" update

# The package would start RabbitMQ right away, with a random Erlang cookie and
# the default node name. policy-rc.d tells the installer not to start services;
# rabbitmq.sh starts it once it's configured.
log "Installing RabbitMQ $RABBITMQ_VERSION"
printf '#!/bin/sh\nexit 101\n' >/usr/sbin/policy-rc.d
chmod 755 /usr/sbin/policy-rc.d
# --no-install-recommends: only what RabbitMQ needs (no Erlang docs, examples or X11).
"${APT[@]}" install --no-install-recommends rabbitmq-server
rm -f /usr/sbin/policy-rc.d

# Erlang and RabbitMQ are upgraded deliberately, one node at a time; never by apt upgrade.
# Only installed packages ("ii"): the pattern also matches Erlang packages apt merely knows about.
mapfile -t HOLD < <(dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' 'erlang-*' rabbitmq-server | awk '$1 == "ii" {print $2}')
apt-mark hold "${HOLD[@]}" >/dev/null
log "Installed $(dpkg-query -W -f='${Package} ${Version}' rabbitmq-server), Erlang $(dpkg-query -W -f='${Version}' erlang-base)"

log "Node prep finished"

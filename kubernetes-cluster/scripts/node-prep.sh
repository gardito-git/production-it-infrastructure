#!/bin/bash
# Runs on every node (etcd, control plane, worker):
# kernel settings, containerd, kubelet/kubeadm/kubectl and the AWS CLI.
source /opt/k8s-bootstrap/lib.sh

log "Disabling swap (kubelet refuses to run with swap on by default)"
swapoff -a
sed -i '/\sswap\s/s/^/#/' /etc/fstab

log "Loading kernel modules and sysctls for container networking"
cat >/etc/modules-load.d/k8s.conf <<'EOF'
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

cat >/etc/sysctl.d/99-kubernetes.conf <<'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system >/dev/null

log "Installing containerd"
"${APT[@]}" update
"${APT[@]}" install apt-transport-https ca-certificates curl gpg containerd

# kubelet and containerd must agree on the cgroup driver; kubeadm uses systemd.
mkdir -p /etc/containerd
containerd config default >/etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
grep -q 'SystemdCgroup = true' /etc/containerd/config.toml ||
  die "could not enable SystemdCgroup in /etc/containerd/config.toml"
systemctl enable containerd
systemctl restart containerd

cat >/etc/crictl.yaml <<'EOF'
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
EOF

log "Installing kubelet, kubeadm and kubectl v$KUBERNETES_VERSION"
mkdir -p /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/v$KUBERNETES_VERSION/deb/Release.key" |
  gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v$KUBERNETES_VERSION/deb/ /" \
  >/etc/apt/sources.list.d/kubernetes.list
"${APT[@]}" update
"${APT[@]}" install kubelet kubeadm kubectl
# Hold them so a routine "apt upgrade" can't upgrade Kubernetes behind kubeadm's back.
apt-mark hold kubelet kubeadm kubectl
systemctl enable kubelet

if ! command -v aws >/dev/null; then
  log "Installing the AWS CLI"
  snap install aws-cli --classic
fi

# Ubuntu's AWS images ship the SSM agent. Access is SSH over the VPN instead,
# so remove it rather than leave an unused agent running.
if snap list amazon-ssm-agent >/dev/null 2>&1; then
  log "Removing the AWS SSM agent"
  snap remove amazon-ssm-agent
fi

if [[ $NODE_ROLE == etcd ]]; then
  # etcd nodes aren't part of the cluster. kubelet runs standalone there,
  # only to keep the etcd static pod running (kubeadm's external etcd setup).
  log "Configuring kubelet as a standalone etcd service manager"
  mkdir -p /etc/systemd/system/kubelet.service.d
  cat >/etc/systemd/system/kubelet.service.d/kubelet.conf <<'EOF'
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
authentication:
  anonymous:
    enabled: false
  webhook:
    enabled: false
authorization:
  mode: AlwaysAllow
cgroupDriver: systemd
address: 127.0.0.1
containerRuntimeEndpoint: unix:///run/containerd/containerd.sock
staticPodPath: /etc/kubernetes/manifests
EOF
  cat >/etc/systemd/system/kubelet.service.d/20-etcd-service-manager.conf <<'EOF'
[Service]
ExecStart=
ExecStart=/usr/bin/kubelet --config=/etc/systemd/system/kubelet.service.d/kubelet.conf
Restart=always
EOF
  systemctl daemon-reload
  systemctl restart kubelet
fi

log "Node prep finished"

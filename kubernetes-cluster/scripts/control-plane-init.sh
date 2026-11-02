#!/bin/bash
# Runs on control-plane-1 only. Creates the cluster with kubeadm init against the
# external etcd, publishes join commands for the other nodes, then installs Cilium.
source /opt/k8s-bootstrap/lib.sh

MY_IP=$(imds local-ipv4)
read -ra ETCD_HOSTS <<<"$ETCD_IPS"

s3_wait control-plane/etcd-client.tar.gz /root/etcd-client.tar.gz
mkdir -p /etc/kubernetes/pki
tar -xzf /root/etcd-client.tar.gz -C /etc/kubernetes/pki
rm -f /root/etcd-client.tar.gz
chmod -R go-rwx /etc/kubernetes/pki

ETCD_ENDPOINTS=""
for host in "${ETCD_HOSTS[@]}"; do
  wait_tcp "$host" 2379
  ETCD_ENDPOINTS+="    - https://$host:2379"$'\n'
done

# While the cluster is being created, no NLB target is healthy yet, so point the
# NLB name at this node. Removed again at the end of this script.
echo "$MY_IP $CONTROL_PLANE_ENDPOINT # k8s-bootstrap" >>/etc/hosts

# Encrypts the control-plane certificates kubeadm uploads into the cluster, so
# control-plane-2 and -3 can download them when they join. Valid for 2 hours.
CERT_KEY=$(kubeadm certs certificate-key)

cat >/etc/kubernetes/kubeadm-config.yaml <<EOF
apiVersion: kubeadm.k8s.io/v1beta4
kind: InitConfiguration
certificateKey: $CERT_KEY
localAPIEndpoint:
  advertiseAddress: $MY_IP
nodeRegistration:
  criSocket: unix:///run/containerd/containerd.sock
---
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
clusterName: $CLUSTER_NAME
kubernetesVersion: $(kubeadm version -o short)
# Every node and kubectl reaches the API through the internal NLB, so any
# control-plane node can fail without breaking the cluster.
controlPlaneEndpoint: "$CONTROL_PLANE_ENDPOINT:6443"
apiServer:
  certSANs:
    - "$CONTROL_PLANE_ENDPOINT"
networking:
  podSubnet: $POD_CIDR
  serviceSubnet: $SERVICE_CIDR
etcd:
  external:
    endpoints:
$ETCD_ENDPOINTS    caFile: /etc/kubernetes/pki/etcd/ca.crt
    certFile: /etc/kubernetes/pki/apiserver-etcd-client.crt
    keyFile: /etc/kubernetes/pki/apiserver-etcd-client.key
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
EOF
# The file holds the certificate key, so keep it root-only.
chmod 600 /etc/kubernetes/kubeadm-config.yaml

log "Running kubeadm init"
kubeadm init --config=/etc/kubernetes/kubeadm-config.yaml --upload-certs

mkdir -p /root/.kube
cp /etc/kubernetes/admin.conf /root/.kube/config
export KUBECONFIG=/etc/kubernetes/admin.conf

log "Publishing join commands"
umask 077
JOIN=$(kubeadm token create --print-join-command --ttl 24h)
echo "$JOIN" >/root/worker-join.sh
echo "$JOIN --control-plane --certificate-key $CERT_KEY" >/root/control-plane-join.sh
s3_put /root/worker-join.sh join/worker.sh
s3_put /root/control-plane-join.sh join/control-plane.sh
rm -f /root/worker-join.sh /root/control-plane-join.sh

log "Installing cilium-cli v$CILIUM_CLI_VERSION"
cd /tmp
CLI_URL="https://github.com/cilium/cilium-cli/releases/download/v$CILIUM_CLI_VERSION/cilium-linux-amd64.tar.gz"
curl -fsSLO "$CLI_URL"
curl -fsSLO "$CLI_URL.sha256sum"
sha256sum --check cilium-linux-amd64.tar.gz.sha256sum
tar -xzf cilium-linux-amd64.tar.gz -C /usr/local/bin
rm -f cilium-linux-amd64.tar.gz cilium-linux-amd64.tar.gz.sha256sum

# ipam.mode=kubernetes makes Cilium use each node's podCIDR from POD_CIDR.
# Cilium's default pool (10.0.0.0/8) would overlap the VPC.
log "Installing Cilium $CILIUM_VERSION"
cilium install --version "$CILIUM_VERSION" --set ipam.mode=kubernetes
cilium status --wait --wait-duration 15m

log "Cluster created. Nodes so far:"
kubectl get nodes -o wide

sed -i '/# k8s-bootstrap$/d' /etc/hosts

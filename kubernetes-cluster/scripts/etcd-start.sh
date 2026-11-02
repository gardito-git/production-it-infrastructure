#!/bin/bash
# Runs on every etcd node. Installs this member's certificates (etcd-2 and
# etcd-3 download them from S3) and starts etcd as a kubelet static pod.
source /opt/k8s-bootstrap/lib.sh

MY_IP=$(imds local-ipv4)

if [[ ! -f /etc/kubernetes/etcd-kubeadmcfg.yaml ]]; then
  s3_wait "etcd/$MY_IP.tar.gz" /root/etcd-bundle.tar.gz
  mkdir -p /root/etcd-bundle /etc/kubernetes
  tar -xzf /root/etcd-bundle.tar.gz -C /root/etcd-bundle
  cp -R /root/etcd-bundle/pki /etc/kubernetes/
  cp /root/etcd-bundle/kubeadmcfg.yaml /etc/kubernetes/etcd-kubeadmcfg.yaml
  rm -rf /root/etcd-bundle /root/etcd-bundle.tar.gz
fi
chmod -R go-rwx /etc/kubernetes/pki

log "Writing the etcd static pod manifest"
kubeadm init phase etcd local --config=/etc/kubernetes/etcd-kubeadmcfg.yaml

# etcd only reports healthy once a quorum (2 of 3) of members is up.
wait_tcp "$MY_IP" 2379
log "etcd is listening on $MY_IP:2379"

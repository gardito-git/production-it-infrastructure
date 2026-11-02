#!/bin/bash
# Runs on control-plane-2 and -3. Joins as an extra control-plane node using the
# command control-plane-1 published. kubeadm downloads the shared certificates
# (including the external etcd client certs) with the certificate key.
source /opt/k8s-bootstrap/lib.sh

umask 077
s3_wait join/control-plane.sh /root/control-plane-join.sh

log "Joining the cluster as a control-plane node"
bash /root/control-plane-join.sh
rm -f /root/control-plane-join.sh

mkdir -p /root/.kube
cp /etc/kubernetes/admin.conf /root/.kube/config
log "Joined as a control-plane node"

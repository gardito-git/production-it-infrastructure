#!/bin/bash
# Runs on etcd-1 only. Creates the etcd CA and a certificate bundle for every
# etcd member, plus the client certificate the API servers use to talk to etcd.
# Follows https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/setup-ha-etcd-with-kubeadm/
source /opt/k8s-bootstrap/lib.sh

read -ra HOSTS <<<"$ETCD_IPS"
WORK=/root/etcd-bundles
mkdir -p "$WORK"
chmod 700 "$WORK"

# initial-cluster lists every member: etcd-1=https://10.0.101.10:2380,...
INITIAL_CLUSTER=""
for i in "${!HOSTS[@]}"; do
  INITIAL_CLUSTER+="${INITIAL_CLUSTER:+,}etcd-$((i + 1))=https://${HOSTS[$i]}:2380"
done

log "Writing a kubeadm etcd config for each member"
for i in "${!HOSTS[@]}"; do
  host=${HOSTS[$i]}
  name=etcd-$((i + 1))
  mkdir -p "$WORK/$host"
  cat >"$WORK/$host/kubeadmcfg.yaml" <<EOF
apiVersion: kubeadm.k8s.io/v1beta4
kind: InitConfiguration
nodeRegistration:
  name: $name
localAPIEndpoint:
  advertiseAddress: $host
---
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
etcd:
  local:
    serverCertSANs:
      - "$host"
    peerCertSANs:
      - "$host"
    extraArgs:
      - name: initial-cluster
        value: $INITIAL_CLUSTER
      - name: initial-cluster-state
        value: new
      - name: name
        value: $name
      - name: listen-peer-urls
        value: https://$host:2380
      - name: listen-client-urls
        value: https://$host:2379
      - name: advertise-client-urls
        value: https://$host:2379
      - name: initial-advertise-peer-urls
        value: https://$host:2380
EOF
done

log "Creating the etcd CA"
kubeadm init phase certs etcd-ca

# kubeadm writes certs into /etc/kubernetes/pki, so generate one member at a
# time, copy the result out, and clear everything except the CA.
# The other members go first; etcd-1's own certs are generated last and stay in place.
for ((i = ${#HOSTS[@]} - 1; i >= 0; i--)); do
  host=${HOSTS[$i]}
  log "Generating certificates for etcd-$((i + 1)) ($host)"
  for cert in etcd-server etcd-peer etcd-healthcheck-client apiserver-etcd-client; do
    kubeadm init phase certs "$cert" --config="$WORK/$host/kubeadmcfg.yaml"
  done
  if ((i > 0)); then
    cp -R /etc/kubernetes/pki "$WORK/$host/"
    find /etc/kubernetes/pki -not -name ca.crt -not -name ca.key -type f -delete
    # Only etcd-1 keeps the CA private key.
    find "$WORK/$host" -name ca.key -type f -delete

    tar -czf "$WORK/$host.tar.gz" -C "$WORK/$host" .
    s3_put "$WORK/$host.tar.gz" "etcd/$host.tar.gz"
  fi
done

log "Uploading the API server's etcd client certificate for the control plane"
tar -czf "$WORK/etcd-client.tar.gz" -C /etc/kubernetes/pki \
  etcd/ca.crt apiserver-etcd-client.crt apiserver-etcd-client.key
s3_put "$WORK/etcd-client.tar.gz" control-plane/etcd-client.tar.gz

# etcd-start.sh reads this member's config from here.
cp "$WORK/${HOSTS[0]}/kubeadmcfg.yaml" /etc/kubernetes/etcd-kubeadmcfg.yaml
rm -rf "$WORK"
log "etcd certificates done"

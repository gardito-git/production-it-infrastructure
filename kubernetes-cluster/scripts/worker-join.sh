#!/bin/bash
# Runs on every worker. Joins the cluster with the command control-plane-1 published.
source /opt/k8s-bootstrap/lib.sh

umask 077
s3_wait join/worker.sh /root/worker-join.sh

log "Joining the cluster as a worker"
bash /root/worker-join.sh
rm -f /root/worker-join.sh
log "Joined as a worker"

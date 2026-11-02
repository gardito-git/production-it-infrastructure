#!/bin/bash
# Entry point, run once at first boot by user-data.sh.tftpl.
# Prepares the OS, then runs the step for this node's role and index.
# Re-run by hand with: sudo /opt/k8s-bootstrap/bootstrap.sh
source /opt/k8s-bootstrap/lib.sh

DONE_MARKER=/var/lib/k8s-bootstrap.done
if [[ -f $DONE_MARKER ]]; then
  log "Already bootstrapped ($DONE_MARKER exists), nothing to do"
  exit 0
fi

"$SCRIPT_DIR/node-prep.sh"

case "$NODE_ROLE/$NODE_INDEX" in
  etcd/0)
    "$SCRIPT_DIR/etcd-certs.sh"
    "$SCRIPT_DIR/etcd-start.sh"
    ;;
  etcd/*) "$SCRIPT_DIR/etcd-start.sh" ;;
  control-plane/0) "$SCRIPT_DIR/control-plane-init.sh" ;;
  control-plane/*) "$SCRIPT_DIR/control-plane-join.sh" ;;
  worker/*) "$SCRIPT_DIR/worker-join.sh" ;;
  *) die "unknown role/index: $NODE_ROLE/$NODE_INDEX" ;;
esac

touch "$DONE_MARKER"
log "Bootstrap finished"

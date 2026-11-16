#!/bin/bash
# Entry point, run once at first boot by user-data.sh.tftpl.
# Every node runs the same steps; Patroni decides which one becomes the primary.
# Re-run by hand with: sudo /opt/pg-bootstrap/bootstrap.sh
source /opt/pg-bootstrap/lib.sh

DONE_MARKER=/var/lib/pg-bootstrap.done
if [[ -f $DONE_MARKER ]]; then
  log "Already bootstrapped ($DONE_MARKER exists), nothing to do"
  exit 0
fi

"$SCRIPT_DIR/node-prep.sh"
"$SCRIPT_DIR/etcd.sh"
"$SCRIPT_DIR/patroni.sh"
"$SCRIPT_DIR/pgbackrest.sh"

# Monitoring agents (pmm-grafana-dashboard module), when enabled. A failure here
# never stops the bootstrap: the server works, it just isn't monitored yet.
if [[ -x $SCRIPT_DIR/monitoring-agent.sh ]]; then
  "$SCRIPT_DIR/monitoring-agent.sh" install "$NODE_NAME" postgresql "" "$SCRIPT_DIR/monitoring-services.sh" ||
    log "WARNING: monitoring agent setup failed; see above"
fi

touch "$DONE_MARKER"
log "Bootstrap finished"

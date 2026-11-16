#!/bin/bash
# Entry point, run once at first boot by user-data.sh.tftpl.
# Re-run by hand with: sudo /opt/redis-bootstrap/bootstrap.sh
source /opt/redis-bootstrap/lib.sh

DONE_MARKER=/var/lib/redis-bootstrap.done
if [[ -f $DONE_MARKER ]]; then
  log "Already bootstrapped ($DONE_MARKER exists), nothing to do"
  exit 0
fi

"$SCRIPT_DIR/node-prep.sh"
"$SCRIPT_DIR/redis.sh"

# Monitoring agents (pmm-grafana-dashboard module), when enabled. A failure here
# never stops the bootstrap: the server works, it just isn't monitored yet.
if [[ -x $SCRIPT_DIR/monitoring-agent.sh ]]; then
  "$SCRIPT_DIR/monitoring-agent.sh" install "$NODE_NAME" redis "" "$SCRIPT_DIR/monitoring-services.sh" ||
    log "WARNING: monitoring agent setup failed; see above"
fi

touch "$DONE_MARKER"
log "Bootstrap finished"

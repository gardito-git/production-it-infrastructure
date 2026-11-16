#!/bin/bash
# Entry point, run once at first boot by user-data.sh.tftpl.
# Re-run by hand with: sudo /opt/rabbitmq-bootstrap/bootstrap.sh
source /opt/rabbitmq-bootstrap/lib.sh

DONE_MARKER=/var/lib/rabbitmq-bootstrap.done
if [[ -f $DONE_MARKER ]]; then
  log "Already bootstrapped ($DONE_MARKER exists), nothing to do"
  exit 0
fi

"$SCRIPT_DIR/node-prep.sh"
"$SCRIPT_DIR/rabbitmq.sh"

# Monitoring agents (pmm-grafana-dashboard module), when enabled. A failure here
# never stops the bootstrap: the server works, it just isn't monitored yet.
if [[ -x $SCRIPT_DIR/monitoring-agent.sh ]]; then
  "$SCRIPT_DIR/monitoring-agent.sh" install "$NODE_NAME" rabbitmq "/var/log/rabbitmq/*.log" "$SCRIPT_DIR/monitoring-services.sh" ||
    log "WARNING: monitoring agent setup failed; see above"
fi

touch "$DONE_MARKER"
log "Bootstrap finished"

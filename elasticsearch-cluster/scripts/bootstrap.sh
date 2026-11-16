#!/bin/bash
# Entry point, run once at first boot by user-data.sh.tftpl.
# Re-run by hand with: sudo /opt/es-bootstrap/bootstrap.sh
source /opt/es-bootstrap/lib.sh

DONE_MARKER=/var/lib/es-bootstrap.done
if [[ -f $DONE_MARKER ]]; then
  log "Already bootstrapped ($DONE_MARKER exists), nothing to do"
  exit 0
fi

# Ubuntu's AWS images ship the SSM agent. Access is SSH over the VPN instead.
if snap list amazon-ssm-agent >/dev/null 2>&1; then
  log "Removing the AWS SSM agent"
  snap remove amazon-ssm-agent
fi

case "$NODE_ROLE" in
  master | data) "$SCRIPT_DIR/elasticsearch.sh" ;;
  kibana) "$SCRIPT_DIR/kibana.sh" ;;
  *) die "unknown role: $NODE_ROLE" ;;
esac

# Monitoring agents (pmm-grafana-dashboard module), when enabled. A failure here
# never stops the bootstrap: the server works, it just isn't monitored yet.
if [[ -x $SCRIPT_DIR/monitoring-agent.sh ]]; then
  "$SCRIPT_DIR/monitoring-agent.sh" install "$NODE_NAME" elasticsearch "/var/log/elasticsearch/*.log /var/log/kibana/*.log" "$SCRIPT_DIR/monitoring-services.sh" ||
    log "WARNING: monitoring agent setup failed; see above"
fi

touch "$DONE_MARKER"
log "Bootstrap finished"

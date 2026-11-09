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

touch "$DONE_MARKER"
log "Bootstrap finished"

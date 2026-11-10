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

touch "$DONE_MARKER"
log "Bootstrap finished"

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

touch "$DONE_MARKER"
log "Bootstrap finished"

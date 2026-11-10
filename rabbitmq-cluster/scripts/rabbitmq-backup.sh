#!/bin/bash
# Run by rabbitmq-backup.timer on every node. Exports the cluster's
# definitions: users (with password hashes), vhosts, permissions, queues,
# exchanges, bindings and policies. NOT the messages themselves: those live on
# the nodes' disks and are replicated by quorum queues.
#
# Definitions are the same on every node, so only one node uploads: the first
# running node by name. Uploads to
#   s3://$BACKUP_BUCKET/$BACKUP_PREFIX/definitions-<timestamp>.json.gz
source /opt/rabbitmq-bootstrap/lib.sh

FIRST=$(rabbitmqctl cluster_status --formatter json | jq -r '.running_nodes | sort | .[0]')
if [[ $FIRST != "rabbit@$NODE_NAME" ]]; then
  log "$FIRST takes the backup, skipping"
  exit 0
fi

STAMP=$(date -u +%Y%m%dT%H%M%SZ)
FILE=$(mktemp)
trap 'rm -f "$FILE"' EXIT

log "Exporting definitions"
rabbitmqctl export_definitions - | gzip >"$FILE"

KEY="$BACKUP_PREFIX/definitions-$STAMP.json.gz"
aws s3 cp --only-show-errors --sse AES256 "$FILE" "s3://$BACKUP_BUCKET/$KEY"
log "Uploaded s3://$BACKUP_BUCKET/$KEY"

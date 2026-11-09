#!/bin/bash
# Run by redis-backup.timer on every node. Only the current master backs up,
# so backups follow the master after a failover. Uploads to
#   s3://$BACKUP_BUCKET/$BACKUP_PREFIX/redis-<timestamp>.rdb.gz
source /opt/redis-bootstrap/lib.sh

PASSWORD=$(secret password)
export REDISCLI_AUTH=$PASSWORD

if [[ $(redis-cli -h 127.0.0.1 role | head -n1) != master ]]; then
  log "Not the master, skipping the backup"
  exit 0
fi

STAMP=$(date -u +%Y%m%dT%H%M%SZ)
FILE=/var/lib/redis/backup-$STAMP.rdb
trap 'rm -f "$FILE" "$FILE.gz"' EXIT

# --rdb asks the server for a fresh, consistent snapshot over the replication
# protocol, so it doesn't depend on when the last automatic save ran.
log "Taking RDB snapshot"
redis-cli -h 127.0.0.1 --rdb "$FILE"
gzip "$FILE"

KEY="$BACKUP_PREFIX/redis-$STAMP.rdb.gz"
aws s3 cp --only-show-errors --sse AES256 "$FILE.gz" "s3://$BACKUP_BUCKET/$KEY"
log "Uploaded s3://$BACKUP_BUCKET/$KEY"

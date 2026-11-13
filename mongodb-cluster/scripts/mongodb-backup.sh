#!/bin/bash
# Run by mongodb-backup.timer on every node. Exactly one member dumps: the first
# healthy SECONDARY in the replica set's own member order, so the primary is
# never loaded and the backup follows failovers. Uploads to
#   s3://$BACKUP_BUCKET/$BACKUP_PREFIX/mongodb-<timestamp>.archive.gz
# Restore: mongorestore --archive=<file> --gzip --oplogReplay (see README).
source /opt/mongodb-bootstrap/lib.sh

MY_IP=${IPS[$NODE_INDEX]}
CONFIG=$(mktemp)
FILE=/var/tmp/mongodb-backup.archive.gz
trap 'rm -f "$CONFIG" "$FILE"' EXIT

# The backup user's password goes in a config file, never on the command line.
chmod 600 "$CONFIG"
printf 'password: "%s"\n' "$(secret backup_password)" >"$CONFIG"

CHOSEN=$(MONGO_BACKUP_PASSWORD=$(secret backup_password) mongosh --quiet --norc \
  "mongodb://127.0.0.1:27017/?directConnection=true" --eval '
    db.getSiblingDB("admin").auth("backup", process.env.MONGO_BACKUP_PASSWORD);
    const m = rs.status().members.find(m => m.stateStr === "SECONDARY" && m.health === 1);
    m ? m.name : ""')
if [[ -z $CHOSEN ]]; then
  log "No healthy secondary in the replica set; no backup today"
  exit 1
fi
if [[ $CHOSEN != "$MY_IP:27017" ]]; then
  log "$CHOSEN takes the backup, skipping"
  exit 0
fi

# --oplog makes the dump consistent to one point in time, even while apps write.
# Written to the root disk first, then uploaded: S3 only ever gets complete files.
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
log "Dumping all databases (from this secondary)"
mongodump --host 127.0.0.1 --port 27017 --username backup --authenticationDatabase admin \
  --config "$CONFIG" --readPreference secondaryPreferred \
  --oplog --gzip --archive="$FILE" --quiet

KEY="$BACKUP_PREFIX/mongodb-$STAMP.archive.gz"
aws s3 cp --only-show-errors --sse AES256 "$FILE" "s3://$BACKUP_BUCKET/$KEY"
log "Uploaded s3://$BACKUP_BUCKET/$KEY ($(du -h "$FILE" | cut -f1))"

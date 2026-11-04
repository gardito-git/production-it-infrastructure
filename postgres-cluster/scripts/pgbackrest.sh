#!/bin/bash
# Configures pgBackRest to keep WAL and backups in S3, and schedules backups.
# Every node gets the same config and timers; only the current primary actually
# backs up (pg-backup.sh checks), so backups follow the primary after a failover.
source /opt/pg-bootstrap/lib.sh

mkdir -p /etc/pgbackrest /var/log/pgbackrest /var/lib/pgbackrest
cat >/etc/pgbackrest/pgbackrest.conf <<EOF
[global]
repo1-type=s3
repo1-s3-bucket=$BACKUP_BUCKET
repo1-s3-region=$AWS_REGION
repo1-s3-endpoint=s3.$AWS_REGION.amazonaws.com
# Credentials come from the instance's IAM role.
repo1-s3-key-type=auto
# The repository's "folder" in the shared private bucket, e.g. /backups/postgres
repo1-path=$BACKUP_PATH
# Keep this many full backups (one per week), plus the WAL to restore to any point in between.
repo1-retention-full=$BACKUP_RETENTION_FULL
compress-type=zst
process-max=2
start-fast=y
log-level-console=info
log-level-file=detail

[main]
pg1-path=$PG_DATA
pg1-socket-path=/var/run/postgresql
EOF
chown -R postgres:postgres /etc/pgbackrest /var/log/pgbackrest /var/lib/pgbackrest
chmod 640 /etc/pgbackrest/pgbackrest.conf

log "Scheduling backups: full on Sunday, differential Monday to Saturday, 01:00 UTC"
cat >/etc/systemd/system/pgbackrest@.service <<EOF
[Unit]
Description=pgBackRest %i backup (runs only on the Patroni primary)
After=patroni.service

[Service]
Type=oneshot
User=postgres
ExecStart=$SCRIPT_DIR/pg-backup.sh %i
EOF

cat >/etc/systemd/system/pgbackrest-full.timer <<'EOF'
[Unit]
Description=Weekly full PostgreSQL backup

[Timer]
OnCalendar=Sun *-*-* 01:00:00 UTC
Persistent=true
Unit=pgbackrest@full.service

[Install]
WantedBy=timers.target
EOF

cat >/etc/systemd/system/pgbackrest-diff.timer <<'EOF'
[Unit]
Description=Daily differential PostgreSQL backup

[Timer]
OnCalendar=Mon..Sat *-*-* 01:00:00 UTC
Persistent=true
Unit=pgbackrest@diff.service

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now pgbackrest-full.timer pgbackrest-diff.timer

# The backup "stanza" (repository layout) is created once, by whichever node is
# primary. Until it exists, archive-push fails and PostgreSQL keeps the WAL locally.
if curl -sf -o /dev/null http://127.0.0.1:8008/primary; then
  log "This node is the primary: creating the pgBackRest stanza"
  for attempt in {1..10}; do
    if sudo -u postgres pgbackrest --stanza=main stanza-create; then
      sudo -u postgres pgbackrest --stanza=main check
      log "Starting the first full backup in the background"
      systemctl start --no-block pgbackrest@full.service
      exit 0
    fi
    log "stanza-create failed (attempt $attempt), retrying"
    sleep 30
  done
  die "could not create the pgBackRest stanza; see /var/log/pgbackrest"
fi
log "This node is a replica: backups will run here only if it becomes primary"

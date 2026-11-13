#!/bin/bash
# Configures mongod on this node and forms the replica set.
#
#   mongodb-1 creates the replica set with itself only, creates the admin and
#   backup users, then adds mongodb-2 and mongodb-3, which copy all data from it
#   (initial sync). After that the three elect a primary among themselves; any
#   member can be primary.
#   mongodb-2/3 just start and wait to be added.
source /opt/mongodb-bootstrap/lib.sh

MY_IP=${IPS[$NODE_INDEX]}

log "Writing the replica set keyfile"
mkdir -p /etc/mongodb
secret keyfile >/etc/mongodb/keyfile
chown mongodb:mongodb /etc/mongodb/keyfile
chmod 400 /etc/mongodb/keyfile

log "Writing /etc/mongod.conf"
cat >/etc/mongod.conf <<EOF
# Written by mongodb.sh at first boot.
storage:
  dbPath: /var/lib/mongodb

systemLog:
  destination: file
  path: /var/log/mongodb/mongod.log
  logAppend: true
  logRotate: reopen   # logrotate sends SIGUSR1, mongod reopens the file

net:
  port: 27017
  # Its own private IP for apps and the other members, localhost for scripts.
  bindIp: 127.0.0.1,$MY_IP

processManagement:
  timeZoneInfo: /usr/share/zoneinfo

replication:
  replSetName: $REPLICA_SET_NAME

security:
  # Login required for everyone (SCRAM). Members prove they belong to the
  # replica set with the shared keyfile.
  authorization: enabled
  keyFile: /etc/mongodb/keyfile
EOF
chown root:mongodb /etc/mongod.conf
chmod 640 /etc/mongod.conf

# Every connection and data file uses a file descriptor. GLIBC_TUNABLES lets
# MongoDB 8.0's allocator use per-CPU caches on Ubuntu 24.04's glibc.
mkdir -p /etc/systemd/system/mongod.service.d
cat >/etc/systemd/system/mongod.service.d/override.conf <<'EOF'
[Unit]
After=mongodb-thp.service
Requires=mongodb-thp.service
RequiresMountsFor=/var/lib/mongodb

[Service]
Environment=GLIBC_TUNABLES=glibc.pthread.rseq=0
LimitNOFILE=64000
LimitNPROC=64000
EOF

cat >/etc/logrotate.d/mongod <<'EOF'
/var/log/mongodb/mongod.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 640 mongodb mongodb
    postrotate
        systemctl kill --signal=SIGUSR1 mongod >/dev/null 2>&1 || true
    endscript
}
EOF

log "Starting mongod"
systemctl daemon-reload
systemctl enable mongod
systemctl restart mongod
for attempt in {1..60}; do
  mongo 'db.hello().ok' >/dev/null 2>&1 && break
  ((attempt == 60)) && die "mongod did not start; see /var/log/mongodb/mongod.log"
  sleep 5
done

if ((NODE_INDEX == 0)); then
  # Safety: if another member already belongs to a replica set, this node is
  # a replacement. Never start a second replica set; it rejoins by itself.
  EXISTING=""
  for ip in "${IPS[@]:1}"; do
    if set_name=$(mongo "$ip" 'db.hello().setName || ""' 2>/dev/null) && [[ -n $set_name ]]; then
      EXISTING=$ip
    fi
  done

  if [[ $(mongo 'db.hello().setName || ""') == "$REPLICA_SET_NAME" ]]; then
    log "Replica set already configured on this node's data"
  elif [[ -n $EXISTING ]]; then
    log "Replica set already running on $EXISTING: not creating a new one, waiting to rejoin"
  else
    log "Creating replica set $REPLICA_SET_NAME with this node"
    mongo "rs.initiate({_id: '$REPLICA_SET_NAME', members: [{_id: 0, host: '$MY_IP:27017'}]})"
    for attempt in {1..60}; do
      [[ $(mongo 'db.hello().isWritablePrimary') == true ]] && break
      ((attempt == 60)) && die "this node did not become primary"
      sleep 2
    done

    # The "localhost exception": the very first user may be created without
    # logging in, from localhost only. After that, login is required.
    log "Creating the admin and backup users"
    MONGO_ADMIN_PASSWORD=$(secret admin_password) MONGO_BACKUP_PASSWORD=$(secret backup_password) \
      mongosh --quiet --norc "mongodb://127.0.0.1:27017/?directConnection=true" --eval '
        const admin = db.getSiblingDB("admin");
        admin.createUser({user: "admin", pwd: process.env.MONGO_ADMIN_PASSWORD, roles: [{role: "root", db: "admin"}]});
        admin.auth("admin", process.env.MONGO_ADMIN_PASSWORD);
        admin.createUser({user: "backup", pwd: process.env.MONGO_BACKUP_PASSWORD,
          roles: [{role: "backup", db: "admin"}, {role: "clusterMonitor", db: "admin"}]});'

    for ip in "${IPS[@]:1}"; do
      log "Waiting for $ip, then adding it to the replica set"
      for attempt in {1..90}; do
        mongo "$ip" 'db.hello().ok' >/dev/null 2>&1 && break
        ((attempt == 90)) && die "$ip did not start mongod within 15 minutes"
        sleep 10
      done
      mongo_admin "if (!rs.conf().members.some(m => m.host === '$ip:27017')) rs.add({host: '$ip:27017'})"
    done
  fi
fi

# Every node: wait until it's a healthy primary or secondary (for mongodb-2/3
# that includes being added and copying all data).
log "Waiting to become PRIMARY or SECONDARY"
for attempt in {1..180}; do
  STATE=$(mongo 'const h = db.hello(); h.isWritablePrimary ? "PRIMARY" : (h.secondary ? "SECONDARY" : "")' 2>/dev/null || true)
  [[ -n $STATE ]] && break
  ((attempt == 180)) && die "not part of a healthy replica set after 30 minutes; see /var/log/mongodb/mongod.log"
  sleep 10
done
log "Member state: $STATE"

log "Scheduling daily backups to s3://$BACKUP_BUCKET/$BACKUP_PREFIX/ (one secondary only)"
cat >/etc/systemd/system/mongodb-backup.service <<EOF
[Unit]
Description=mongodump to S3 (only on the chosen secondary)

[Service]
Type=oneshot
ExecStart=$SCRIPT_DIR/mongodb-backup.sh
EOF

cat >/etc/systemd/system/mongodb-backup.timer <<'EOF'
[Unit]
Description=Daily MongoDB backup

[Timer]
OnCalendar=*-*-* 01:00:00 UTC
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now mongodb-backup.timer
log "MongoDB node ready"

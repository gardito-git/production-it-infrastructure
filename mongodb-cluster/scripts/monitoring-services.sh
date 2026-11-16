#!/bin/bash
# Registers this member's MongoDB with PMM. Run by monitoring-agent (retried
# every 5 minutes until it succeeds).
#
# The primary creates the "pmm" monitoring user once (roles from PMM's docs:
# clusterMonitor, read on local, and explainRole); the other members get it
# through replication. Until then, pmm-admin's connection check fails and this
# is retried.
source /opt/mongodb-bootstrap/lib.sh
source /etc/monitoring-agent/env

PMM_SERVICE="$NODE_NAME-mongodb"
pmm-admin list 2>/dev/null | grep -qw "$PMM_SERVICE" && exit 0

export MONGO_PMM_PASSWORD
MONGO_PMM_PASSWORD=$(secret pmm_password)

if [[ $(mongo 'db.hello().isWritablePrimary') == true ]]; then
  log "Creating the pmm monitoring user"
  mongo_admin '
    const admin = db.getSiblingDB("admin");
    if (!admin.getRole("explainRole")) {
      admin.createRole({
        role: "explainRole",
        privileges: [
          { resource: { db: "", collection: "" },
            actions: ["dbHash", "collStats", "dbStats", "find", "indexStats", "listIndexes", "listCollections"] },
          { resource: { db: "", collection: "system.profile" },
            actions: ["dbStats", "collStats", "indexStats"] }
        ],
        roles: []
      });
    }
    const roles = [{ role: "explainRole", db: "admin" }, { role: "clusterMonitor", db: "admin" }, { role: "read", db: "local" }];
    if (admin.getUser("pmm")) {
      admin.updateUser("pmm", { pwd: process.env.MONGO_PMM_PASSWORD, roles: roles });
    } else {
      admin.createUser({ user: "pmm", pwd: process.env.MONGO_PMM_PASSWORD, roles: roles });
    }'
fi

pmm-admin add mongodb --username=pmm --password="$MONGO_PMM_PASSWORD" \
  --host=127.0.0.1 --port=27017 --service-name="$PMM_SERVICE" \
  --cluster="$REPLICA_SET_NAME" --replication-set="$REPLICA_SET_NAME" \
  --environment="$PMM_ENVIRONMENT"

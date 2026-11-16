#!/bin/bash
# Registers this node's PostgreSQL with PMM. Run by monitoring-agent (retried
# every 5 minutes until it succeeds).
#
# The primary creates the "pmm" monitoring user (role pg_monitor) and the
# pg_stat_statements extension; replicas receive both through replication.
# Query analytics reads pg_stat_statements, which patroni.sh preloads.
source /opt/pg-bootstrap/lib.sh
source /etc/monitoring-agent/env

PMM_SERVICE="$NODE_NAME-postgresql"
pmm-admin list 2>/dev/null | grep -qw "$PMM_SERVICE" && exit 0

export PMM_PASSWORD
PMM_PASSWORD=$(secret pmm_password)
MY_IP=$(imds local-ipv4)

psql_local() {
  runuser -u postgres -- psql -X -q -v ON_ERROR_STOP=1 "$@"
}

if [[ $(psql_local -tAc 'SELECT pg_is_in_recovery()') == f ]]; then
  log "Creating the pmm monitoring user"
  # \getenv reads the password from the environment, so it's not on a command line.
  psql_local <<'SQL'
\getenv pw PMM_PASSWORD
SELECT 'CREATE ROLE pmm LOGIN' WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'pmm') \gexec
ALTER ROLE pmm WITH LOGIN PASSWORD :'pw' CONNECTION LIMIT 10;
GRANT pg_monitor TO pmm;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
SQL
fi

if [[ $(psql_local -tAc "SELECT count(*) FROM pg_roles WHERE rolname = 'pmm'") != 1 ]]; then
  log "The pmm user hasn't reached this replica yet"
  exit 1
fi

# The node's own IP: pg_hba allows the VPC range with a password.
pmm-admin add postgresql --username=pmm --password="$PMM_PASSWORD" \
  --host="$MY_IP" --port=5432 --service-name="$PMM_SERVICE" \
  --query-source=pgstatements --environment="$PMM_ENVIRONMENT" --cluster="$CLUSTER_NAME"

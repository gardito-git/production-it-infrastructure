#!/bin/bash
# Run by the pgbackrest@full / pgbackrest@diff systemd units on every node.
# Backs up only if this node is the current Patroni primary.
set -euo pipefail

TYPE=${1:?usage: pg-backup.sh full|diff|incr}

if ! curl -sf -o /dev/null http://127.0.0.1:8008/primary; then
  echo "Not the primary, skipping the $TYPE backup"
  exit 0
fi

exec pgbackrest --stanza=main --type="$TYPE" backup

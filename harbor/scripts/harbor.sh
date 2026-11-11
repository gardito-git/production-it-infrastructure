#!/bin/bash
# Installs Harbor with Docker Compose, listening on localhost:8080 over plain
# HTTP. The host's Nginx (harbor-nginx.sh) handles TLS and access rules.
source /opt/harbor-bootstrap/lib.sh

log "Downloading Harbor $HARBOR_VERSION"
TARBALL=harbor-online-installer-v$HARBOR_VERSION.tgz
curl -fsSL --retry 5 -o "/tmp/$TARBALL" \
  "https://github.com/goharbor/harbor/releases/download/v$HARBOR_VERSION/$TARBALL"
echo "$HARBOR_INSTALLER_SHA256  /tmp/$TARBALL" | sha256sum -c - || die "checksum mismatch for $TARBALL"
tar -xzf "/tmp/$TARBALL" -C /opt
rm -f "/tmp/$TARBALL"

log "Reading passwords from Secrets Manager"
export HARBOR_ADMIN_PASSWORD HARBOR_DB_PASSWORD DOMAIN_NAME AWS_REGION S3_BUCKET DATA_DIR
HARBOR_ADMIN_PASSWORD=$(secret admin_password)
HARBOR_DB_PASSWORD=$(secret database_password)

# Start from the template shipped with this version, so its defaults and
# _version stay correct, and change only what's specific to this setup.
log "Writing $HARBOR_DIR/harbor.yml"
python3 - "$HARBOR_DIR/harbor.yml.tmpl" "$HARBOR_DIR/harbor.yml" <<'PY'
import os
import sys
import yaml

with open(sys.argv[1]) as f:
    config = yaml.safe_load(f)

domain = os.environ["DOMAIN_NAME"]
config["hostname"] = domain
config["external_url"] = f"https://{domain}"
config["http"] = {"port": 8080}
config.pop("https", None)  # TLS ends at the host's Nginx
config["harbor_admin_password"] = os.environ["HARBOR_ADMIN_PASSWORD"]
config["database"]["password"] = os.environ["HARBOR_DB_PASSWORD"]
config["data_volume"] = os.environ["DATA_DIR"]
# No access keys: the registry uses the instance's IAM role.
config["storage_service"] = {
    "s3": {
        "region": os.environ["AWS_REGION"],
        "bucket": os.environ["S3_BUCKET"],
        "secure": True,
        "v4auth": True,
    }
}

with open(sys.argv[2], "w") as f:
    yaml.safe_dump(config, f, sort_keys=False)
PY
chmod 600 "$HARBOR_DIR/harbor.yml" # holds the passwords

cd "$HARBOR_DIR"
log "Generating Harbor's configuration"
./prepare --with-trivy

# Harbor publishes its port on every interface by default. Only the host's
# Nginx should reach it, and Nginx is what enforces the access rules.
sed -i -E 's/^( *- )(")?8080:8080(")?$/\1127.0.0.1:8080:8080/' docker-compose.yml
grep -q '127.0.0.1:8080:8080' docker-compose.yml || die "could not bind Harbor to localhost in docker-compose.yml"

# Docker restarts the containers after a reboot on its own, but in any order.
# This also makes sure /data is mounted first.
cat >/etc/systemd/system/harbor.service <<EOF
[Unit]
Description=Harbor container registry
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target
RequiresMountsFor=$DATA_DIR

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$HARBOR_DIR
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=900

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable harbor.service

log "Starting Harbor (this pulls its images)"
docker compose up -d

for attempt in {1..60}; do
  STATUS=$(curl -s http://127.0.0.1:8080/api/v2.0/health | jq -r .status 2>/dev/null || true)
  [[ $STATUS == healthy ]] && break
  ((attempt == 60)) && die "Harbor is not healthy after 10 minutes; see: cd $HARBOR_DIR && docker compose ps"
  sleep 10
done
log "Harbor is healthy"

# harbor_api METHOD PATH [JSON]: call Harbor's API as admin. The password goes
# through a file descriptor so it never shows up in the process list.
harbor_api() {
  curl -fsS -X "$1" "http://127.0.0.1:8080/api/v2.0$2" -H 'Content-Type: application/json' \
    ${3:+-d "$3"} --config <(printf 'user = "admin:%s"\n' "$HARBOR_ADMIN_PASSWORD") -o /dev/null
}

# The Docker API is on the internet, and Harbor's default "library" project
# allows anonymous pulls. Make it private.
log "Making the default project private"
harbor_api PUT /projects/library '{"metadata":{"public":"false"}}' ||
  log "WARNING: could not make the library project private; do it in the UI"

# Deleting an image only removes the reference. Garbage collection frees the
# layers in S3, every Sunday at 04:00 UTC.
log "Scheduling weekly garbage collection"
harbor_api POST /system/gc/schedule \
  '{"schedule":{"type":"Custom","cron":"0 0 4 * * 0"},"parameters":{"delete_untagged":true,"workers":1}}' ||
  log "Garbage collection schedule not created (normal when reusing an existing data volume)"

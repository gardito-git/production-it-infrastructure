#!/bin/bash
# Run at first boot and by harbor-certificate.timer until HTTPS is up. Waits for
# your public DNS record, gets the certificate, and enables port 443.
# Renewals are handled afterwards by certbot's own timer.
source /opt/harbor-bootstrap/lib.sh

LIVE=/etc/letsencrypt/live/$DOMAIN_NAME
SITE=/etc/nginx/sites-available/harbor-https.conf
ENABLED=/etc/nginx/sites-enabled/harbor-https.conf

enable_https() {
  [[ -e $ENABLED ]] && return 0
  log "Enabling HTTPS for $DOMAIN_NAME"
  cat >"$SITE" <<EOF
# Written by harbor-certificate.sh.
server {
    listen 443 ssl;
    server_name _;

    ssl_certificate     $LIVE/fullchain.pem;
    ssl_certificate_key $LIVE/privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_session_cache   shared:harbor_ssl:10m;
    add_header Strict-Transport-Security "max-age=31536000" always;

    # The Docker API: open to everyone, Harbor checks the login.
    location /v2/ {
        include snippets/harbor-proxy.conf;
    }

    # docker login gets its token here; rate limited from the internet.
    location = /service/token {
        limit_req zone=harbor_login burst=60 nodelay;
        include snippets/harbor-proxy.conf;
    }

    # Everything else (web UI, management API): VPC and VPN only.
    location / {
        if (\$harbor_internal = 0) {
            return 403;
        }
        include snippets/harbor-proxy.conf;
    }
}
EOF
  ln -sf "$SITE" "$ENABLED"
  nginx -t
  systemctl reload nginx
  log "HTTPS is up"
}

if [[ -f $LIVE/fullchain.pem ]]; then
  enable_https
  exit 0
fi

# Ask a public resolver: inside the VPC this name resolves to the private IP.
RESOLVED=$(dig +short +time=5 +tries=2 @1.1.1.1 A "$DOMAIN_NAME" | tail -n 1 || true)
if [[ $RESOLVED != "$PUBLIC_IP" ]]; then
  log "Waiting for the public DNS record: $DOMAIN_NAME -> $PUBLIC_IP (currently '${RESOLVED:-none}')"
  exit 0
fi

log "Requesting a Let's Encrypt certificate for $DOMAIN_NAME"
certbot certonly --webroot --webroot-path /var/www/acme \
  --domain "$DOMAIN_NAME" --non-interactive --agree-tos --register-unsafely-without-email \
  --keep-until-expiring
enable_https

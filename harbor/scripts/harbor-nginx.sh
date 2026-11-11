#!/bin/bash
# The host's Nginx in front of Harbor: port 80 for Let's Encrypt, and the access
# rules. HTTPS comes up as soon as the certificate exists (harbor-certificate.sh).
source /opt/harbor-bootstrap/lib.sh

mkdir -p /var/www/acme

log "Writing the Nginx configuration"
rm -f /etc/nginx/sites-enabled/default

cat >/etc/nginx/conf.d/harbor-access.conf <<EOF
# Written by harbor-nginx.sh at first boot.
# Only the connection's real address counts, never a header a client could fake.
# VPC addresses are VPN users (the VPN translates them), Kubernetes and runners.
geo \$harbor_internal {
    default     0;
    127.0.0.0/8 1;
    $VPC_CIDR   1;
}

# Slows down password guessing from the internet. An empty key isn't limited,
# so clients inside the VPC never are.
map \$harbor_internal \$harbor_login_limit_key {
    0 \$binary_remote_addr;
    1 "";
}
limit_req_zone \$harbor_login_limit_key zone=harbor_login:10m rate=30r/m;
limit_req_status 429;
EOF

cat >/etc/nginx/snippets/harbor-proxy.conf <<'EOF'
proxy_pass http://127.0.0.1:8080;
proxy_http_version 1.1;
proxy_set_header Connection "";
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto https;

# Image layers can be many GB: no size limit, stream instead of buffering to
# disk, and allow slow uploads from developers' home connections.
client_max_body_size 0;
proxy_request_buffering off;
proxy_buffering off;
proxy_read_timeout 900s;
proxy_send_timeout 900s;
EOF

cat >/etc/nginx/sites-available/harbor-http.conf <<'EOF'
# Written by harbor-nginx.sh at first boot.
server {
    listen 80 default_server;
    server_name _;

    # Let's Encrypt fetches its validation file from here.
    location /.well-known/acme-challenge/ {
        root /var/www/acme;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}
EOF
ln -sf /etc/nginx/sites-available/harbor-http.conf /etc/nginx/sites-enabled/harbor-http.conf

nginx -t
systemctl enable nginx
systemctl reload-or-restart nginx

# Reload Nginx whenever certbot renews the certificate (kept on the data volume).
mkdir -p /etc/letsencrypt/renewal-hooks/deploy
cat >/etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh <<'EOF'
#!/bin/sh
systemctl reload nginx
EOF
chmod 755 /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh

# Keeps trying until the DNS record exists. 15 minutes stays under Let's
# Encrypt's limit of 5 failed validations per hour.
cat >/etc/systemd/system/harbor-certificate.service <<EOF
[Unit]
Description=Get Harbor's Let's Encrypt certificate and enable HTTPS
After=network-online.target nginx.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$SCRIPT_DIR/harbor-certificate.sh
EOF

cat >/etc/systemd/system/harbor-certificate.timer <<'EOF'
[Unit]
Description=Retry Harbor's certificate until it exists

[Timer]
OnBootSec=1min
OnUnitActiveSec=15min

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now harbor-certificate.timer
"$SCRIPT_DIR/harbor-certificate.sh" || log "No certificate yet; harbor-certificate.timer keeps retrying"

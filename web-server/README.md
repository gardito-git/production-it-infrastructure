# Web servers: Nginx on EC2 behind CloudFront and an internal ALB

Three identical Nginx servers, one per AZ, in **private subnets**, behind an **internal**
Application Load Balancer (ALB). Visitors come only through **CloudFront**, which reaches the
ALB privately via a VPC origin. Nginx is the reverse proxy for the Next.js frontend
(`nextjs-pm2-frontend`), and can host other sites too.

```
                                  ┌──────────────────────── VPC (private subnets a, b, c) ───────────────────────┐
browser ──HTTPS──► CloudFront ────┼─ VPC origin ──► ALB :80 (internal, health checks GET /healthz)              │
                                  │                   ├──► web-1 (AZ a) ─┐                                       │
                                  │                   ├──► web-2 (AZ b) ─┼─ Nginx ──► Next.js frontend .70:3000  │
                                  │                   └──► web-3 (AZ c) ─┘                                       │
you (VPN) ──22────────────────────┼──► web-1/2/3                                                                 │
                                  └──────────────────────────────────────────────────────────────────────────────┘
```

| Piece | Details |
|---|---|
| CloudFront | The only public entry point; HTTPS for visitors. The distribution lives in `nextjs-pm2-frontend` |
| VPC origin | `cloudfront.tf`: CloudFront's private way into the internal ALB. Any distribution can use it (`cloudfront_vpc_origin_id`) |
| ALB | Internal, in the private subnets, port 80. Drops malformed headers |
| Health checks | `GET /healthz` every 10 s; a server failing 3 checks stops getting traffic, 2 passes bring it back |
| Servers | `instance_count` (3) × `c8i.large`, Ubuntu 24.04, IMDSv2, encrypted gp3 root, no public IP |
| Nginx | Installed at first boot by `scripts/nginx.sh.tftpl`. Default site: test page at `/`, `/healthz`. Next.js site: `scripts/nextjs-site.conf.tftpl` |
| Security groups | VPC (CloudFront VPC origin) → ALB on 80; ALB → servers on 80; SSH only from the VPN |

### Why internal, and not a public ALB?

CloudFront terminates HTTPS for visitors and reaches the ALB through a VPC origin, from network
interfaces inside the VPC. So the ALB needs **no public IP, no certificate and no IP
allow-list**, and nobody can bypass CloudFront (and its caching, or a WAF later) by calling the
ALB directly. The hop from CloudFront to the ALB stays inside AWS's network.

## The Next.js site

When `nextjs_upstreams` is set (root `main.tf` passes `module.nextjs_frontend.upstream_servers`),
first boot writes `/etc/nginx/sites-available/<first domain>.conf` (e.g. `example.com.conf`, or
`nextjs-frontend.conf` without a domain) and enables it with a symlink in `sites-enabled/`:

- `upstream nextjs_frontend` with the Next.js servers' fixed IPs (`10.0.10x.70:3000`), keepalive
  connections, and passive failover (a failing server is skipped for 10 s; GETs are retried on another).
- `server_name` = your domains (`nextjs_server_names`) plus `*.cloudfront.net`.
- `Host`, `X-Forwarded-For`, `X-Forwarded-Host` and `X-Forwarded-Proto: https` passed to Next.js.

The template is commented line by line; read it to see every setting.

## Files

| File | What's in it |
|---|---|
| `alb.tf` | Internal load balancer, target group (health checks), HTTP listener |
| `cloudfront.tf` | CloudFront VPC origin for the ALB |
| `compute.tf` | AMI lookup, key pair, the instances |
| `security-groups.tf` | ALB and server security groups and rules |
| `scripts/nginx.sh.tftpl` | First-boot script: Nginx, test page, `/healthz`, real client IPs, the Next.js site |
| `scripts/nextjs-site.conf.tftpl` | The Next.js reverse-proxy site (`sites-available/<domain>.conf`) |
| `variables.tf` / `outputs.tf` | Module inputs and outputs |

## Usage

```hcl
module "web_server" {
  source = "./web-server"

  project_name = var.project_name
  environment  = var.environment

  vpc_id             = module.vpc.vpc_id
  vpc_cidr           = module.vpc.vpc_cidr
  private_subnet_ids = module.vpc.private_subnet_ids # internal ALB and servers

  ssh_public_key               = var.ssh_public_key
  ssh_source_security_group_id = module.vpc.vpn_security_group_id

  nextjs_upstreams    = module.nextjs_frontend.upstream_servers
  nextjs_server_names = module.nextjs_frontend.domain_names
}
```

After `terraform apply`, open `terraform output -raw frontend_url` (the site through
CloudFront). Over the VPN:

```bash
curl "http://$(terraform output -raw web_alb_dns_name)/"   # test page: refresh to see web-1, -2, -3
ssh ubuntu@<private-ip>
sudo tail -f /var/log/web-server-bootstrap.log             # first-boot log
```

## Domains and HTTPS

HTTPS is handled by CloudFront, not here: point your domain at **CloudFront**
(`frontend_cloudfront_domain`), never at this ALB. Set `domain_names` and an ACM certificate
**in us-east-1** on the `nextjs_frontend` module (see its README); Nginx's `server_name` follows
automatically for new servers.

Nginx sees the visitor's IP in `X-Forwarded-For` (`/etc/nginx/conf.d/real-ip.conf` makes it log
the real IP).

## Managing Nginx config

The three servers must serve the same config. Edit it in one place, never by hand
on each server:

- New servers get the config from `scripts/nginx.sh.tftpl` and `scripts/nextjs-site.conf.tftpl`
  (user data runs only at first boot). For running servers, push the same file to all of them
  (Ansible, or copy it), one server at a time.
- **Always run `sudo nginx -t` before `sudo systemctl reload nginx`.**
- While a server is broken, the ALB health check takes it out of rotation, so visitors keep
  getting the healthy ones.

## Cost (rough)

Internal ALB about $16/month + usage (LCUs), and 3× `c8i.large`. No public IPv4 charges: neither
the ALB nor the servers have public IPs. CloudFront VPC origins cost nothing extra.

## TO-DO

- [ ] AWS WAF on the CloudFront distribution
- [ ] Config management for Nginx sites on running servers (Ansible or similar)

# Web servers: Nginx on EC2 behind an Application Load Balancer

Three identical Nginx servers, one per AZ, in **private subnets**. The internet
reaches them only through a public **Application Load Balancer (ALB)**.

```
                       ┌───────────── public subnets ─────────────┐
internet ──80/443────► │  ALB  (health checks GET /healthz)       │
                       └──────┬──────────────┬──────────────┬─────┘
                              │ :80          │ :80          │ :80
                       ┌──────▼──────┐ ┌─────▼──────┐ ┌─────▼──────┐
                       │ web-1 (AZ a)│ │web-2 (AZ b)│ │web-3 (AZ c)│  private subnets,
you (VPN) ──22───────► └─────────────┘ └────────────┘ └────────────┘  no public IPs
```

| Piece | Details |
|---|---|
| ALB | Public, in the public subnets. Port 80 (and 443 with a certificate). Drops malformed headers |
| Health checks | `GET /healthz` every 10 s; a server failing 3 checks stops getting traffic, 2 passes bring it back |
| Servers | `instance_count` (3) × `instance_type` (`c8i.large`), Ubuntu 24.04, IMDSv2, encrypted gp3 root, no public IP |
| Nginx | Installed at first boot by `scripts/nginx.sh.tftpl`. Test page at `/` shows which server answered |
| Security groups | Internet → ALB on 80/443; ALB → servers on 80 only; SSH only from the VPN |

### Why an ALB here (and an NLB for Kubernetes and PostgreSQL)?

This is plain HTTP traffic, which is what an ALB is built for: it understands requests,
health-checks the app itself, terminates TLS with one free ACM certificate, and can do
path/host routing or a WAF later. The Kubernetes API and PostgreSQL need raw TCP
end to end, so those use NLBs.

## Files

| File | What's in it |
|---|---|
| `alb.tf` | Load balancer, target group (health checks), HTTP and optional HTTPS listeners |
| `compute.tf` | AMI lookup, key pair, the instances |
| `security-groups.tf` | ALB and server security groups and rules |
| `scripts/nginx.sh.tftpl` | First-boot script: Nginx, test page, `/healthz`, real client IPs |
| `variables.tf` / `outputs.tf` | Module inputs and outputs |

## Usage

```hcl
module "web_server" {
  source = "./web-server"

  project_name = var.project_name
  environment  = var.environment

  vpc_id             = module.vpc.vpc_id
  vpc_cidr           = module.vpc.vpc_cidr
  public_subnet_ids  = module.vpc.public_subnet_ids  # the ALB
  private_subnet_ids = module.vpc.private_subnet_ids # the servers

  ssh_public_key               = var.ssh_public_key
  ssh_source_security_group_id = module.vpc.vpn_security_group_id

  # certificate_arn = "arn:aws:acm:..."  # enables HTTPS, see below
}
```

After `terraform apply`:

```bash
curl "http://$(terraform output -raw web_alb_dns_name)/"   # refresh a few times: web-1, web-2, web-3
ssh ubuntu@<private-ip>                                    # over the VPN
sudo tail -f /var/log/web-server-bootstrap.log             # first-boot log
```

Point your domain at the ALB: a Route 53 **alias** record (`alb_dns_name` + `alb_zone_id`),
or a CNAME at another DNS provider. Never use the ALB's IPs; they change.

## HTTPS

1. Request a certificate for your domain in **AWS Certificate Manager**, in the same region
   as the ALB, and validate it (DNS validation; AWS renews it automatically).
2. Pass its ARN as `certificate_arn` and apply. Port 443 then serves HTTPS (TLS 1.2/1.3),
   and port 80 redirects to it.

The servers keep speaking plain HTTP to the ALB inside the VPC. Nginx sees the original
scheme in `X-Forwarded-Proto` and the visitor's IP in `X-Forwarded-For`
(`/etc/nginx/conf.d/real-ip.conf` makes Nginx log the real visitor IP).

## Managing Nginx config

The three servers must serve the same config. Edit it in one place, never by hand
on each server:

- Keep the site config (`/etc/nginx/sites-available/<site>` and its symlink in
  `sites-enabled/`) in git and push it to all servers the same way (Ansible, a deploy
  script, or `scripts/nginx.sh.tftpl` for new servers).
- **Always run `sudo nginx -t` before `sudo systemctl reload nginx`.**
- Change one server at a time. While a server is broken, the ALB health check takes it
  out of rotation, so visitors keep getting the healthy ones.

## Cost (rough, us-east-1)

ALB about $16/month + usage (LCUs), and 3× `c8i.large`. There are no public IPv4 charges
for the servers any more (they have none); the ALB has its own.

## TO-DO

- [ ] HTTPS: ACM certificate → `certificate_arn`
- [ ] Route 53 alias record for the domain
- [ ] Config management for Nginx sites (Ansible or similar)

# Harbor on EC with Dedicated S3
You will need this if you work for Military, Hospital, Bank, Laws or Goverment.
Using public registry is like AWS ECR/DockerHub is not wise.

## What it builds

```
Developers (no VPN) ──:443──► Elastic IP ─┐  host Nginx (TLS, access rules)
Let's Encrypt ────────:80───► Elastic IP ─┤     internet: only /v2/* and /service/token
                                          ├──►  VPC/VPN:  everything
VPN, Kubernetes, runners ──:443──► .90 ───┘         │
                                                    ▼
                                    Harbor (Docker Compose, 127.0.0.1:8080)
                                      ├─ image layers ──► dedicated S3 bucket
                                      └─ PostgreSQL, Redis, keys, Trivy DB ──► 100 GiB EBS at /data
```

| | |
|---|---|
| Server | 1 × `m8i.xlarge` (4 vCPU, 16 GiB), Ubuntu 24.04, public subnet, Elastic IP, fixed private IP `.90` |
| Storage | 30 GiB gp3 root; 100 GiB gp3 data volume at `/data` with daily snapshots (30 kept) |
| Images | Dedicated private S3 bucket, using Harbor's S3 driver and the server's IAM role (no AWS keys) |
| Version | Harbor **2.15.4**, with Trivy for vulnerability scanning |
| Certificate | Let's Encrypt (certbot, HTTP-01), renewed automatically |

## Who can reach what

`harbor.example.com` is one name that resolves differently depending on where you are:

| From | Resolves to | Can use |
|---|---|---|
| Internet | Elastic IP (your public DNS) | `docker login`, `push`, `pull` only. Everything else returns **403** |
| VPN, or inside the VPC | Private IP `.90` (Route 53 private zone) | Everything, including the web UI |

Nginx decides by the connection's real source address, never by a header. VPN traffic arrives
from a VPC address, and the private zone is visible to VPN users because the VPN uses the VPC's
DNS resolver.

## Setup

1. Set `domain_name` in the root `module "harbor"` block to your real name (Let's Encrypt
   refuses `example.com`), then `terraform apply`.
2. **Create one public DNS record** at your DNS provider (GoDaddy, Cloudflare...):

   | Type | Name | Value |
   |---|---|---|
   | A | `harbor` | `terraform output -raw harbor_public_ip` |

   On Cloudflare, set it to **DNS only** (grey cloud). Its proxy limits upload size, which breaks
   pushing large layers.
3. Wait. The server retries every 15 minutes until the record exists, then gets the certificate
   and enables HTTPS. Harbor itself is already running by then.
4. Connect the VPN, open `https://harbor.example.com` and log in as `admin`:

   ```bash
   aws secretsmanager get-secret-value --secret-id "$(terraform output -raw harbor_secret_arn)" \
     --query SecretString --output text | jq -r .admin_password
   ```

5. In the UI (over the VPN): create a project per team, **keep them private**, create a user per
   developer, and use a **robot account** for each CI pipeline or Kubernetes cluster.

By running this module you accept the Let's Encrypt Subscriber Agreement: first boot passes
`--agree-tos` to certbot.

## Using it

From anywhere, without the VPN:

```bash
docker login harbor.example.com
docker tag my-app:1.0 harbor.example.com/my-team/my-app:1.0
docker push harbor.example.com/my-team/my-app:1.0
```

Set up accounts first over the VPN. Passwords are managed in the UI.

## What first boot sets up for you

- The default `library` project is made **private** (Harbor ships it public, and the Docker API
  is on the internet).
- **Garbage collection** every Sunday at 04:00 UTC. Deleting an image only removes its
  reference; this step frees the layers in S3.
- **Restart order:** `harbor.service` starts Harbor after a reboot, and only once `/data` is mounted.

## Things to know

- **The server is directly on the internet** (ports 80 and 443). Harbor's login is exposed through
  `/service/token`, so use long passwords and robot accounts. Nginx limits login attempts from the
  internet to 30 per minute per address (with short bursts). Clients in the VPC aren't limited.
- **Keep Harbor patched.** Read the release notes, upgrade one version at a time, and take a
  snapshot first (see the Harbor upgrade guide). `harbor_version` only affects a new server.
- **Certificate expiry:** certbot renews about 30 days before the 90-day certificate expires and
  needs port 80 and the DNS record to stay as they are. Let's Encrypt no longer emails expiry
  warnings, so monitor it (TO-DO below). Check with `sudo certbot certificates`.
- **`/data` matters as much as S3.** S3 has the layers, but only PostgreSQL knows which layers make
  up which image. `/data/secret` also holds the keys that decrypt Harbor's stored credentials.
- **Restoring:** create a volume from the latest snapshot in the same AZ and swap it in as
  `/data`. Changes since the last snapshot (03:30 UTC daily) are lost.
- **One server:** if it's down, pushes and new pulls fail. Images already on nodes keep running.
- **Pulls go directly to S3.** Harbor redirects Docker clients to short-lived signed S3 links, so
  large downloads skip the server.
- **Replacing the server** (`terraform apply -replace=module.harbor.aws_instance.harbor`): the Elastic IP, data
  volume and certificate are kept, so the DNS record doesn't change.

## Operating

```bash
ssh ubuntu@<private-ip>                              # over the VPN
sudo tail -f /var/log/harbor-bootstrap.log           # first boot
cd /opt/harbor && sudo docker compose ps             # Harbor's containers
systemctl list-timers 'harbor-certificate*'          # certificate retries
sudo journalctl -u harbor-certificate.service        # certificate log
sudo certbot certificates                            # certificate expiry
```

## Files

| File | What's in it |
|---|---|
| `compute.tf` | Server, Elastic IP, data volume, daily snapshots |
| `s3.tf` | Dedicated bucket for image layers |
| `dns.tf` | Route 53 private zone: the name's private IP for the VPC and VPN |
| `iam.tf` | Server role (secret, bucket); snapshot role |
| `secret-manager.tf` | Admin and database passwords |
| `security-groups.tf` | 80 and 443 from anywhere, SSH from the VPN |
| `scripts/harbor.sh` | Installs and configures Harbor |
| `scripts/harbor-nginx.sh` | The front Nginx and its access rules |
| `scripts/harbor-certificate.sh` | Waits for DNS, gets the certificate, enables HTTPS |

## Inputs

| Name | Default | Description |
|---|---|---|
| `project_name`, `environment` | (required) | Used in resource names |
| `vpc_id`, `vpc_cidr` | (required) | The VPC; its addresses get full access |
| `public_subnet_id` | (required) | Where the server runs |
| `ssh_public_key`, `vpn_security_group_id` | (required) | SSH key; the VPN may SSH in |
| `domain_name` | (required) | Harbor's public name |
| `harbor_version` / `harbor_installer_sha256` | `"2.15.4"` / its checksum | Change them together |
| `snapshot_retention_count` | `30` | Daily snapshots kept |

## Outputs

`public_ip`, `private_ip`, `url`, `bucket_name`, `secret_arn`.

## TO-DO

- [ ] Alert on certificate expiry and on low disk space on `/data`
- [ ] Tag retention rules per project, so old images get cleaned up
- [ ] Configure Kubernetes nodes and runners to pull with robot accounts

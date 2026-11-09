# Classic/Manual NextJS on EC2 with PM2 and Ansible
because AWS Amplify/Vercel are expensive and Serverless Nextjs Plugin are no longer maintained (https://www.serverless.com/plugins/serverless-nextjs-plugin).

You can use Open Next JS (https://opennext.js.org/) or SST (https://v2.sst.dev/start/nextjs),

but I don't write Typescript, sorry I'm too lazy. IF your Frontend Team are really good, then this is not for you.

## What it builds

```
                                ┌──────────────────── VPC (private subnets a, b, c) ───────────────────┐
browser ──HTTPS──► CloudFront ──┼─ VPC origin ──► internal ALB :80 ──► frontend-1/2/3 :3000 (PM2)     │
                     │          └──────────────────────────────────────────────────────────────────────┘
                     └─ /_next/static/* ──► S3 bucket (private, read by CloudFront only)
```

| Path | Served by | Cached at the edge |
|---|---|---|
| `/_next/static/*` (JS, CSS, fonts) | S3 | 1 year: file names are hashed, so they never change |
| `/_next/image*` (next/image) | Next.js | Per image, width, quality and format |
| Everything else (pages, API routes, server actions) | Next.js | No, always fresh |

- **3 servers** (`r8i.xlarge`: 4 vCPU, 32 GiB, one per AZ), Ubuntu 24.04, Node.js 24 and PM2 in
  **cluster mode**: **3 Next.js processes per server, 4 GiB each**, running as the unprivileged
  `frontend` user. That's 9 processes in total behind the ALB.
- **The ALB is internal** (no public IP). CloudFront reaches it through a
  [VPC origin](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-vpc-origins.html),
  so nobody can skip CloudFront and hit the servers or the ALB directly.
- **HTTPS** at CloudFront: free `*.cloudfront.net` certificate, or your domain (see Custom domain).
- **SSH only over the VPN**, IMDSv2 only, encrypted disks, same as the other modules.

## Why build once and upload, not `git pull` on every server

With static files in S3, **every server must run the exact same build**. `next build` on each
server gives each one a different build ID and chunks, so a page rendered by frontend-1 can ask for
JS that only exists on frontend-2, and visitors get errors. So the app is built **once**
(on one Linux machine or WSL), uploaded to S3, and every server downloads that same file.
Bonus: servers need no git credentials, no build tools, and deploys take seconds.

## One-time: your Next.js project

In `next.config.js` (or `.mjs` / `.ts`):

```js
module.exports = {
  output: "standalone", // a self-contained server.js with only the node_modules it needs
};
```

Optional but recommended: a cheap health route, e.g. `app/api/health/route.js` returning `ok`,
and set `health_check_path = "/api/health"`. The default `/` renders a full page every 10 s per ALB node.

## How to deploy

**1. Release** (build once, upload). From your Next.js project folder, on **Linux x86_64**
(WSL or a Linux machine, because `sharp` and other native modules are compiled for the
build machine), with **Node.js 24** and AWS credentials of someone in the `web_developers` group:

```bash
/path/to/nextjs-pm2-frontend/scripts/release.sh v1.4.2 "$(terraform output -raw frontend_bucket_name)"
```

It uploads `.next/static` to `s3://<bucket>/_next/static/` (cached 1 year) and the server bundle
to `s3://<bucket>/releases/v1.4.2.tar.gz`. A version can only be uploaded once.

**2. Deploy** to the servers **one at a time** (connect the VPN first):

```bash
ssh ubuntu@<frontend-1 ip> sudo deploy-frontend v1.4.2
```

`deploy-frontend` downloads the release, switches `/opt/frontend/current` to it, runs
`pm2 reload` (restarts the processes one by one, so **no request is dropped**), waits until the
health check answers, then saves it as the live version (`releases/CURRENT`). If the new version
is unhealthy it stops and says so. Don't continue to the next server; fix it or roll back.

**Rollback:** the same command with the previous version: `sudo deploy-frontend v1.4.1`.
The last 5 releases stay on disk, so it takes seconds.

A **replaced or new server** deploys `releases/CURRENT` by itself at first boot.

### Every new tag: one command with Ansible (recommended)

Instead of SSH-ing into each server, run the playbook in `ansible/` from **WSL or Linux**
(Ansible doesn't run on Windows), connected to the VPN. It finds the servers itself (by
their `Role = nextjs-frontend` tag) and deploys **one at a time**. If one server fails it
**stops**, so the other two keep serving the old version.

One-time setup:

```bash
pip install ansible-core boto3          # or: sudo apt install ansible python3-boto3
cd nextjs-pm2-frontend/ansible
ansible-galaxy collection install -r requirements.yml
# edit inventory.aws_ec2.yml: region, Project and Environment tags
ansible-inventory --graph               # should list frontend-1, -2, -3
```

Then for every new tag:

```bash
# Build + upload + rolling deploy:
ansible-playbook deploy.yml -e version=v1.4.2 -e app_dir=~/code/my-next-app \
  -e bucket=$(terraform -chdir=../.. output -raw frontend_bucket_name)

# Already released with release.sh? Only deploy:
ansible-playbook deploy.yml -e version=v1.4.2

# Rollback:
ansible-playbook deploy.yml -e version=v1.4.1
```

Servers that already run that version are skipped, so after a failure you can simply fix
it and run the same command again.

## Runtime settings and secrets

Put server-side variables (`DATABASE_URL`, API keys...) in `/etc/frontend/app.env` on every server,
one `KEY=value` per line, then `sudo deploy-frontend <current version>` to apply them.
`NEXT_PUBLIC_*` variables are different: Next.js bakes them into the JS **at build time**, so
they must be set when you run `release.sh`.

## PM2 cluster mode and memory

Each server runs **3 Next.js processes** (PM2 calls them *instances*; they're ordinary Node.js
processes, not containers). They all listen on port 3000 together: PM2's cluster mode hands
incoming connections to them in turn, so the ALB still sees one target per server.

```
ALB ──► frontend-1 :3000 ──► PM2 ─┬─ Next.js #0  (max 4 GiB)
                                  ├─ Next.js #1  (max 4 GiB)
                                  └─ Next.js #2  (max 4 GiB)
```

Why several processes: one Node.js process uses one CPU core at most. Three processes use
three of the four vCPUs; the fourth is left for the OS, PM2 and the image optimizer (`sharp`).
If one process crashes or is restarted for memory, the other two keep serving.

| Variable | Default | PM2 setting | What happens at the limit |
|---|---|---|---|
| `pm2_instances` | `3` | `instances: 3` | Processes per server. Keep it ≤ vCPUs (4) |
| `node_heap_mb` | `3072` | `node_args: --max-old-space-size=3072` | Node's garbage collector works harder, then the process crashes ("heap out of memory") and PM2 restarts it |
| `max_memory_restart_mb` | `4096` | `max_memory_restart: 4096M` | PM2 restarts the process gracefully (checked about every 30 s) |

**Memory budget on `r8i.xlarge` (32 GiB):** 3 × 4 GiB = 12 GiB, plus 4 GiB for the one extra
process that briefly exists during `pm2 reload` (new one starts before the old one stops), plus
~2 GiB for the OS = 18 GiB. Plenty of headroom. `max_memory_restart` is total memory (RSS:
heap + buffers + native code), so it must be above the heap; Terraform refuses otherwise.

A process restarting often for memory (`sudo frontend-pm2 list`, the restart count ↺) means a
leak or a too-small limit; check `sudo frontend-pm2 monit` before simply raising it.

**Changing it on running servers:** new values only reach new servers (user data runs once).
On a running one, edit `instances` / `node_args` / `max_memory_restart` in `/etc/frontend/ecosystem.config.js`,
then `sudo frontend-pm2 delete frontend && sudo deploy-frontend <live version>`. A plain
`pm2 reload` keeps the old process options. This restarts that server's processes at once, so
do one server at a time and wait until the ALB shows it healthy again.

## Operating

```bash
sudo frontend-pm2 list          # processes, CPU, memory, restarts
sudo frontend-pm2 logs          # live logs (rotated by pm2-logrotate)
sudo frontend-pm2 monit         # live dashboard
readlink /opt/frontend/current   # which version is live
sudo tail -f /var/log/frontend-bootstrap.log          # first boot
```

PM2 starts on every boot (`pm2-frontend` systemd service) with the last deployed version.

## Custom domain

1. Request an ACM certificate for `www.example.com` **in us-east-1** (a CloudFront rule, whatever
   region the rest runs in) and validate it.
2. In the root `module "nextjs_frontend"` block set `domain_names = ["www.example.com"]` and
   `acm_certificate_arn = "arn:aws:acm:us-east-1:..."`, then apply.
3. Point the domain at `terraform output frontend_cloudfront_domain` (CNAME, or Route 53 alias).

## Things to know

- **Never delete `_next/static/`.** Visitors with an open tab still have old HTML that asks
  for old chunks. The files are small; let them accumulate.
- **Pages are not cached by CloudFront.** Fine for SSR and logged-in pages. If you have
  pages that are the same for everyone (marketing, ISR), a later step is a cache behavior that
  respects Next.js's `Cache-Control` for those paths.
- **Cache invalidation is rarely needed:** static files are hashed and pages aren't cached.
  For a changed `next/image` source with the same URL:
  `aws cloudfront create-invalidation --distribution-id <id> --paths "/_next/image*"`.
- **Server actions need the real `Host` header**, which is why CloudFront forwards all viewer
  headers to Next.js (`Managed-AllViewer`). Don't change that policy to one that drops `Host`.
- **The ALB accepts port 80 from the VPC CIDR.** CloudFront's VPC origin connects from IPs inside
  the VPC; the ALB has no public IP, so the internet can't use that rule.
- **`user_data` and `ami` are ignored after creation:** script changes apply to new servers only.

## Files

| File | What's in it |
|---|---|
| `compute.tf` | AMI, key pair, the servers |
| `alb.tf` | Internal ALB, target group (port 3000), health check |
| `cloudfront.tf` | VPC origin, distribution, cache behaviors, next/image cache policy |
| `s3.tf` | Bucket for `_next/static/` and `releases/`, CloudFront-only read policy |
| `iam.tf` | Servers: read releases. Deployers: upload releases and static files |
| `security-groups.tf` | 80 from the VPC to the ALB, 3000 from the ALB, SSH from the VPN |
| `scripts/bootstrap.sh.tftpl` | First boot: Node.js, PM2, `deploy-frontend`, `frontend-pm2` |
| `scripts/release.sh` | Build once and upload (run on WSL or a Linux machine) |
| `ansible/` | Rolling deploy of a release to all servers, one at a time (`deploy.yml`) |

## Inputs

| Name | Default | Description |
|---|---|---|
| `project_name`, `environment` | (required) | Used in resource names |
| `vpc_id`, `vpc_cidr`, `private_subnet_ids` | (required) | The VPC and its private subnets |
| `ssh_public_key`, `ssh_source_security_group_id` | (required) | SSH key; the VPN may SSH in |
| `deployer_group_name` | `null` | IAM group that may release (root: `web_developers`) |
| `instance_count` | `3` | Servers (type `r8i.xlarge`, set in `compute.tf`) |
| `pm2_version` | `"6"` | Node.js major (24) is set in `compute.tf`; must match what you build with |
| `pm2_instances` | `3` | Next.js processes per server (cluster mode) |
| `node_heap_mb` / `max_memory_restart_mb` | `3072` / `4096` | Per process: V8 heap, and PM2 restart at this RSS (MiB) |
| `app_port` / `health_check_path` | `3000` / `"/"` | Next.js port, health check (2xx/3xx = healthy) |
| `domain_names` / `acm_certificate_arn` | `[]` / `null` | Custom domain (certificate in us-east-1) |
| `cloudfront_price_class` | `"PriceClass_200"` | Includes Asia |

## Outputs

`url`, `cloudfront_domain`, `cloudfront_zone_id`, `distribution_id`, `bucket_name`, `private_ips`, `instance_ids`.

## TO-DO

- [ ] AWS WAF on the distribution (rate limiting, managed rule sets)
- [ ] CloudFront caching for public, same-for-everyone pages

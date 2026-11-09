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

- **3 servers** (`c8i.large`, one per AZ), Ubuntu 24.04, Node.js 24 and PM2 in **cluster mode**:
  one Next.js process per vCPU, running as the unprivileged `frontend` user.
- **The ALB is internal** (no public IP). CloudFront reaches it through a
  [VPC origin](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-vpc-origins.html),
  so nobody can skip CloudFront and hit the servers or the ALB directly.
- **HTTPS** at CloudFront: free `*.cloudfront.net` certificate, or your domain (see Custom domain).
- **SSH only over the VPN**, IMDSv2 only, encrypted disks, same as the other modules.

## Why build once and upload, not `git pull` on every server

With static files in S3, **every server must run the exact same build**. `next build` on each
server gives each one a different build ID and chunks, so a page rendered by frontend-1 can ask for
JS that only exists on frontend-2, and visitors get errors. So the app is built **once**
(CI, or one Linux machine), uploaded to S3, and every server downloads that same file.
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
(CI, WSL, or a Linux machine, because `sharp` and other native modules are compiled for the
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

# Already released (e.g. by CI)? Only deploy:
ansible-playbook deploy.yml -e version=v1.4.2

# Rollback:
ansible-playbook deploy.yml -e version=v1.4.1
```

Servers that already run that version are skipped, so after a failure you can simply fix
it and run the same command again.

### Release automatically on every tag (GitHub Actions)

Then a tag does the build and upload by itself; you only run the deploy.

```
git push origin v1.4.2 ──► GitHub Actions: release.sh ──► S3      (automatic)
ansible-playbook deploy.yml -e version=v1.4.2             (you, over the VPN)
```

1. In the root `module "nextjs_frontend"` block set `github_repository = "my-org/my-next-app"`
   and apply. This creates an IAM role that **only `v*` tag runs of that repository** can use,
   through GitHub's OIDC tokens, so **no AWS keys are stored in GitHub**. If your account
   already has a GitHub OIDC provider (only one may exist), pass its ARN as
   `github_oidc_provider_arn`.
2. In the Next.js repository, copy `github/release.yml` to `.github/workflows/release.yml` and
   `scripts/release.sh` to `scripts/release.sh` (`chmod +x`, or `git update-index --chmod=+x`).
3. In that repository's **Settings → Secrets and variables → Actions → Variables**, add
   `AWS_ROLE_ARN` (`terraform output -raw frontend_github_release_role_arn`), `AWS_REGION` and
   `FRONTEND_BUCKET` (`terraform output -raw frontend_bucket_name`), plus any `NEXT_PUBLIC_*`
   build variables (and list them under `env:` in the workflow).

The run summary shows the exact deploy command. The deploy stays manual on purpose: someone
decides when production changes, and the servers stay reachable only over the VPN.

## Runtime settings and secrets

Put server-side variables (`DATABASE_URL`, API keys...) in `/etc/frontend/app.env` on every server,
one `KEY=value` per line, then `sudo deploy-frontend <current version>` to apply them.
`NEXT_PUBLIC_*` variables are different: Next.js bakes them into the JS **at build time**, so
they must be set when you run `release.sh`.

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
| `scripts/release.sh` | Build once and upload (run on CI or a Linux machine) |
| `ansible/` | Rolling deploy of a release to all servers, one at a time (`deploy.yml`) |
| `github-actions.tf` | OIDC role so GitHub Actions can release on `v*` tags (when `github_repository` is set) |
| `github/release.yml` | Workflow to copy into your Next.js repository |

## Inputs

| Name | Default | Description |
|---|---|---|
| `project_name`, `environment` | (required) | Used in resource names |
| `vpc_id`, `vpc_cidr`, `private_subnet_ids` | (required) | The VPC and its private subnets |
| `ssh_public_key`, `ssh_source_security_group_id` | (required) | SSH key; the VPN may SSH in |
| `deployer_group_name` | `null` | IAM group that may release (root: `web_developers`) |
| `instance_count` / `instance_type` | `3` / `"c8i.large"` | Servers |
| `node_major` / `pm2_version` | `24` / `"6"` | Must match what you build with |
| `app_port` / `health_check_path` | `3000` / `"/"` | Next.js port, health check (2xx/3xx = healthy) |
| `domain_names` / `acm_certificate_arn` | `[]` / `null` | Custom domain (certificate in us-east-1) |
| `cloudfront_price_class` | `"PriceClass_200"` | Includes Asia |
| `github_repository` / `github_oidc_provider_arn` | `null` / `null` | Next.js repo that may release on tags; existing OIDC provider to reuse |

## Outputs

`url`, `cloudfront_domain`, `cloudfront_zone_id`, `distribution_id`, `bucket_name`, `private_ips`, `instance_ids`, `github_release_role_arn`.

## TO-DO

- [ ] AWS WAF on the distribution (rate limiting, managed rule sets)
- [ ] CloudFront caching for public, same-for-everyone pages

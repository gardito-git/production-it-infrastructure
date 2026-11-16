# Percona Monitoring and Management with Grafana Dashboard

Self-hosted PMM with Grafana Dashboard if you want stay away from AWS CloudWatch. This is good
considering we have self-hosted database clusters: one server collects the metrics and logs of
every other server in this project.

## What it builds

```
every server: pmm-agent (+ exporters) ──push :443──► monitoring server (r8i.xlarge, private, .110)
every server: Grafana Alloy (logs)    ──push :3100─►   ├─ PMM 3: Grafana, metrics (VictoriaMetrics),
Kubernetes:   k8s-monitoring chart    ──:9090/:3100─►  │         Query Analytics (ClickHouse)
                                                       ├─ Loki ─────────────► S3 (logs)
                                                       └─ Prometheus (Kubernetes metrics)
VPN users ──► https://monitoring.internal  (GitHub login, view-only)
```

| | |
|---|---|
| Server | 1 × `r8i.xlarge` (4 vCPU, 32 GiB), private subnet, fixed IP `.110`, Docker |
| Storage | 30 GiB root + 100 GiB gp3 data volume (PMM and Prometheus data), daily snapshots (7 kept) |
| Logs | Loki, stored in a dedicated S3 bucket, kept 30 days |
| Retention | 30 days for metrics and logs (`retention_days`), metrics every 5 seconds |
| Versions | PMM 3.10.0, Loki 3.7.10, Prometheus 3.16.0, Alloy (latest), k8s-monitoring chart 4.6.1 |
| Access | `https://monitoring.internal`, over the VPN only |

## What is monitored

| Service | Metrics | Logs | How |
|---|---|---|---|
| **Every server** (Linux) | CPU, memory, disk, network | systemd journal | `pmm-agent` + Alloy, installed at first boot |
| PostgreSQL | Database + **Query Analytics** | journal | `pmm-admin add postgresql`, `pg_stat_statements` |
| MongoDB | Database, replica set | `mongod.log` | `pmm-admin add mongodb` |
| Redis | Database | journal | `pmm-admin add valkey` (PMM's Redis/Valkey exporter) |
| RabbitMQ | Queues, connections | `/var/log/rabbitmq` | RabbitMQ's own Prometheus endpoint (`:15692`) |
| Elasticsearch | Cluster, nodes, indices | `/var/log/elasticsearch`, Kibana | `elasticsearch_exporter` on the Kibana node |
| Nginx (web servers) | Connections, requests | `/var/log/nginx` | `nginx-prometheus-exporter` + `stub_status` |
| Harbor | Registry metrics | `/var/log/harbor` | Harbor's built-in metrics (`:9090`) |
| Next.js | Server only (Linux) | PM2 logs | App-level metrics need code in the app (frontend team) |
| GitHub runners | Server only (Linux) | Runner logs | |
| **Kubernetes** | Nodes, pods, workloads | Every pod's logs | `k8s-monitoring` Helm chart (Alloy in the cluster) |

The database, exporter and Kubernetes parts are each module's `scripts/monitoring-services.sh`.

## How agents find the server

1. At first boot, the monitoring server creates a PMM **service account token** and stores it in
   Secrets Manager (`agent-token` secret).
2. Every server's first-boot script installs `pmm-client` and Alloy, then retries every 5 minutes
   (`monitoring-register.timer`) until the token exists, registers with PMM, and adds its
   databases or exporters. So the servers and the monitoring server can boot in any order.
3. Metrics are **pushed** to PMM over HTTPS (443) and logs to Loki (3100): the monitoring server
   never connects into other servers.

Each server's IAM role may read the token secret and nothing else (policy `*-monitoring-agent`).

## Setup

1. `terraform apply` (the root module wires the agents into every module).
2. Connect the VPN and open **https://monitoring.internal**. PMM uses a **self-signed certificate**,
   so your browser warns once; accept it. Log in as `admin`:

   ```bash
   aws secretsmanager get-secret-value --secret-id "$(terraform output -raw monitoring_admin_secret_arn)" \
     --query SecretString --output text | jq -r .password
   ```

3. Servers appear within a few minutes in **PMM Inventory**; logs in **Explore → Loki**; Kubernetes
   in **Dashboards → Kubernetes**.

### Sign in with GitHub (organization members, view-only)

1. In GitHub: **your organization → Settings → Developer settings → OAuth Apps → New**:
   - Homepage URL: `https://monitoring.internal/graph/`
   - Callback URL: `https://monitoring.internal/graph/login/github`

   (GitHub only redirects your browser there, so a private name works.)
2. Store the app's credentials:

   ```bash
   aws secretsmanager put-secret-value --secret-id "$(terraform output -raw monitoring_github_secret_arn)" \
     --secret-string '{"client_id":"...","client_secret":"..."}'
   ```

3. Apply them (recreates the PMM container; data stays): on the server,
   `sudo /opt/monitoring-bootstrap/monitoring.sh`.

Everyone who signs in starts as **Viewer**. Promote people in **Administration → Users**; keep
`admin` for yourself. The organization comes from `github_runner_scope` in `terraform.tfvars`.

### Slack alerts

Create them in the UI once Grafana is up: **Alerting → Contact points → New → Slack** (an
incoming-webhook URL), then alert rules on the panels you care about (disk space, replication
lag, a server not reporting). See Grafana's
[contact points guide](https://grafana.com/docs/grafana/latest/alerting/configure-notifications/manage-contact-points/).

## Servers that already exist

Terraform only runs first-boot scripts on **new** servers. For servers created before this
module, use the playbook in `ansible/` (WSL or Linux, on the VPN):

```bash
cd pmm-grafana-dashboard/ansible
terraform -chdir=../.. output -raw monitoring_agent_script > agent.sh
ansible-galaxy collection install amazon.aws          # once; needs boto3
# edit inventory.aws_ec2.yml: region, Project and Environment tags
ansible-playbook install-agents.yml -e project=example -e env=dev
```

It matches each server by its Name tag, copies the installer and the module's hook, and installs.
Two services need one manual step on existing servers:

- **PostgreSQL Query Analytics** needs `pg_stat_statements` preloaded (new clusters have it):
  `patronictl edit-config` → add `shared_preload_libraries: pg_stat_statements` and
  `pg_stat_statements.track: all` under `postgresql.parameters`, then
  `patronictl restart <cluster>` (rolling, one member at a time).
- **Harbor metrics**: add `metric: {enabled: true, port: 9090, path: /metrics}` to
  `/opt/harbor/harbor.yml`, then `cd /opt/harbor && sudo ./prepare --with-trivy && sudo docker compose up -d`
  (and bind 9090 to 127.0.0.1 in `docker-compose.yml`, as `harbor.sh` does).

## Operating

```bash
ssh ubuntu@<monitoring-ip>                                 # over the VPN
sudo tail -f /var/log/monitoring-bootstrap.log             # first boot
sudo docker ps                                             # pmm-server, loki, prometheus
sudo docker logs -f pmm-server                             # or loki / prometheus
df -h /data                                                # metrics disk

# on any monitored server
sudo pmm-admin status ; sudo pmm-admin list                # agent and its services
systemctl status alloy                                     # log shipping
sudo journalctl -u monitoring-register.service             # registration attempts
```

## Things to know

- **One server.** If it's down, dashboards and alerts stop; the monitored services are not
  affected (agents buffer briefly, then drop data).
- **Self-signed certificate** on the UI (PMM's default). Agents connect with
  `--server-insecure-tls`. For a trusted certificate, put one in `/data/pmm/nginx/` (see PMM docs).
- **Disk.** 100 GiB holds 30 days of 5-second metrics for this project's ~45 servers. Watch
  `df -h /data`; grow the EBS volume and `xfs_growfs /data` if needed, or lower `retention_days`.
- **Logs cost little:** Loki compresses them in S3 and its compactor deletes them after 30 days.
  Don't add an S3 lifecycle rule on the Loki bucket; it could delete data Loki still references.
- **Passwords on the command line.** `pmm-admin add` takes database passwords as flags, visible
  in the process list for the moment it runs (root-only servers, VPN-only access).
- **MongoDB Query Analytics** reads the database profiler, which is off by default. Turn it on
  per database if you want it (`db.setProfilingLevel(1, {slowms: 100})`).
- **AWS Client VPN** metrics exist only in CloudWatch, so they aren't here.

## Files

| File | What's in it |
|---|---|
| `compute.tf` | The server, data volume, daily snapshots |
| `s3.tf` | Loki's bucket |
| `secret-manager.tf` | Admin password, agent token (filled by the server), GitHub OAuth (filled by you) |
| `iam.tf` | Server role; the agents' read-the-token policy; snapshot role |
| `security-groups.tf` | 443, 3100, 9090 from the VPC; SSH from the VPN |
| `dns.tf` | Private zone for `monitoring.internal` |
| `agent.tf`, `agent/monitoring-agent.sh` | The agent installer handed to every other module |
| `scripts/monitoring.sh` | PMM, Loki and Prometheus containers |
| `scripts/grafana-setup.sh` | Agent token, data sources, Kubernetes dashboards |
| `ansible/` | Agents for servers that existed before this module |

## Inputs

| Name | Default | Description |
|---|---|---|
| `project_name`, `environment` | (required) | Resource names; `environment` is also PMM's environment label |
| `vpc_id`, `vpc_cidr`, `private_subnet_id` | (required) | Where the server runs; who may send data |
| `ssh_public_key`, `vpn_security_group_id` | (required) | SSH key; the VPN may SSH in |
| `domain_name` | `"monitoring.internal"` | The UI's private name |
| `github_organization` | `null` | Organization allowed to sign in with GitHub |
| `pmm_version` / `loki_version` / `prometheus_version` | `"3.10.0"` / `"3.7.10"` / `"3.16.0"` | Image tags |
| `retention_days` | `30` | Metrics and logs |
| `snapshot_retention_count` | `7` | Daily data volume snapshots kept |

## Outputs

`url`, `private_ip`, `admin_secret_arn`, `github_secret_arn`, `loki_bucket_name`, `agent`
(for the other modules' `monitoring` input), `agent_script`.

## TO-DO

- [ ] Slack contact point and alert rules (disk, replication lag, server down, error logs)
- [ ] Next.js application metrics (ask the frontend team: `prom-client` or OpenTelemetry)
- [ ] A trusted TLS certificate for the UI

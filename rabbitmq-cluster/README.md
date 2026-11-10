# RabbitMQ cluster on EC2

A self-managed, highly available RabbitMQ cluster on plain EC2, because Amazon MQ/SQS too expensive.

3 nodes, one per AZ, in the private subnets. They install, cluster and configure themselves at
first boot, so `terraform apply` is the only step.

```
                 ┌──────────────────── VPC (private subnets a, b, c) ────────────────────┐
  apps (pods) ──►│  :5672 AMQP (login required)                                           │
                 │   rabbitmq-1 .80 (a)    rabbitmq-2 .80 (b)    rabbitmq-3 .80 (c)       │
                 │        ◄──── Erlang clustering :4369 / :25672 (nodes only) ────►        │
  you (VPN) ────►│  :15672 management UI, :22 SSH                                         │
                 └──────── daily definitions export ─► S3 backups/rabbitmq/ ──────────────┘
```

| | |
|---|---|
| Nodes | 3 × `r8i.large` (2 vCPU, 16 GiB), Ubuntu 24.04, fixed IPs `.80` |
| Storage | 30 GiB gp3 root, encrypted; RabbitMQ's data in `/var/lib/rabbitmq` |
| Version | RabbitMQ **4.3** + Erlang 27, from Team RabbitMQ's apt repository (pinned, held) |
| Default queue type | **Quorum** (replicated to all 3 nodes) |
| Access | AMQP from the VPC; management UI and SSH from the VPN only; no TLS |

## Is RabbitMQ in memory? Do messages survive a restart?

RabbitMQ **writes to disk; no add-on is needed.** RAM is a working buffer. What survives a
restart of RabbitMQ or the EC2 instance depends on how apps declare queues and send messages:

| | After a restart |
|---|---|
| **Quorum queue** (the default here) + persistent message | ✅ Kept: on disk on all 3 nodes |
| Classic **durable** queue + persistent message (`delivery_mode=2`) | ✅ Kept, but on one node only |
| Transient (non-durable) queue, or non-persistent message | ❌ Lost |

**Quorum queues** use Raft, like etcd: a message is confirmed only once a majority (2 of 3)
has written it to disk. Losing a node (or an AZ) loses no confirmed message, and the queue
keeps working. The old "mirrored classic queues" were removed in RabbitMQ 4.0.

For no message loss, apps should also:
- use **publisher confirms** (the broker confirms each message once it's safely stored), and
- **ack** messages only after processing them (manual acknowledgements).

## Using it

**Management UI:** connect the VPN and open `terraform output -raw rabbitmq_management_url`
(`http://10.0.101.80:15672`; any node works). Log in as `admin`:

```bash
aws secretsmanager get-secret-value --secret-id "$(terraform output -raw rabbitmq_secret_arn)" \
  --query SecretString --output text | jq -r .password
```

**Give each app its own user** instead of `admin` (UI → Admin → Users, or on a node):

```bash
sudo rabbitmqctl add_user orders-service '<password>'
sudo rabbitmqctl set_permissions -p / orders-service '^orders\..*' '^orders\..*' '^orders\..*'
```

**Apps** get all three addresses (`terraform output rabbitmq_amqp_endpoints`); most clients
take a list and reconnect to another node if one fails:

```
amqp://orders-service:<password>@10.0.101.80:5672,10.0.102.80:5672,10.0.103.80:5672/
```

(Exact syntax depends on the client library; some take a list of hosts instead of one URL.)

**Queues an app declares without a type become quorum queues.** Exceptions that stay classic:
exclusive or auto-delete queues (temporary reply queues, for example), because a quorum queue
must be durable. That's fine: those hold nothing worth keeping.

## Operating the cluster

On any node (SSH over the VPN):

```bash
sudo rabbitmqctl cluster_status              # running nodes, alarms
sudo rabbitmq-diagnostics check_running      # health of this node
sudo rabbitmqctl list_queues name type messages leader members
sudo rabbitmq-queues check_if_node_is_quorum_critical   # before stopping a node
sudo tail -f /var/log/rabbitmq-bootstrap.log # first boot
ls /var/log/rabbitmq/                        # RabbitMQ's own logs
```

Prometheus metrics: `http://<node>:15692/metrics` (open to the VPC).

**Backups:** every night at 02:30 UTC, one node exports the **definitions** (users, vhosts,
permissions, queues, exchanges, bindings, policies) to `s3://<private bucket>/backups/rabbitmq/`,
kept 30 days. Messages are not backed up: they're in flight by nature, and quorum queues keep
3 copies. To restore definitions on a new cluster:
`sudo rabbitmqctl import_definitions definitions.json`.

## Things to know

- **Restart or reboot one node at a time**, and check `rabbitmq-queues
  check_if_node_is_quorum_critical` first. With 2 of 3 nodes up, every quorum queue keeps
  working; with 1 of 3 they stop accepting messages until a second node is back (no data lost).
- **Disk (30 GiB root).** Below **5 GB free** RabbitMQ blocks all publishers until consumers
  catch up (a "disk alarm"). A big backlog of unconsumed messages fills the disk; watch queue
  lengths. If you expect large backlogs, a separate, bigger EBS volume for `/var/lib/rabbitmq`
  is the next step.
- **Memory.** Above **60% of RAM** (~9.6 GiB) RabbitMQ blocks publishers too (a "memory alarm").
- **Replacing a node** (terminated instance, `terraform apply -replace=...`): the cluster still
  remembers the old node's name. Before the new one boots, on a running node:
  `sudo rabbitmqctl forget_cluster_node rabbit@rabbitmq-2`. Once the new node has joined, put
  it back into the quorum queues: `sudo rabbitmq-queues grow rabbit@rabbitmq-2 all`.
- **The Erlang cookie is the cluster's master key.** Anyone with it and access to port 25672
  controls the cluster, so that port is open only between the nodes. Never open 4369/25672 to the VPC.
- **Upgrades:** one node at a time (patch and minor versions, e.g. 4.3 → 4.4), then enable new
  feature flags once all nodes run it (`sudo rabbitmqctl enable_feature_flag all`). Bump
  `rabbitmq_version` so new nodes match. Read the release notes before a minor upgrade.
- **Passwords cross the VPC unencrypted** (no TLS, like Elasticsearch). Port 5672 is reachable
  from inside the VPC only, and VPN traffic is encrypted. Never expose it publicly.

## Files

| File | What's in it |
|---|---|
| `compute.tf` | AMI, key pair, the 3 nodes on fixed IPs |
| `secret-manager.tf` | Admin password and Erlang cookie |
| `security-groups.tf` | AMQP + metrics from the VPC, clustering between nodes, UI + SSH from the VPN |
| `iam.tf` | Read the secret; upload backups to `backups/rabbitmq/` |
| `scripts/` | First boot: `node-prep.sh` (hostname, install), `rabbitmq.sh` (config, cluster, quorum default, backup timer), `rabbitmq-backup.sh` |

## Inputs

| Name | Default | Description |
|---|---|---|
| `project_name`, `environment` | (required) | Used in resource names |
| `vpc_id`, `vpc_cidr` | (required) | The VPC; its CIDR may use AMQP and metrics |
| `private_subnet_ids`, `private_subnet_cidrs` | (required) | Exactly 3; nodes get `.80` in each |
| `ssh_public_key`, `vpn_security_group_id` | (required) | SSH key; the VPN may SSH in and open the UI |
| `backup_bucket_name`, `backup_bucket_arn` | (required) | The private bucket from the `s3` module |
| `backup_prefix` | `"backups/rabbitmq"` | Where definitions backups go |
| `rabbitmq_version` | `"4.3"` | Minor version; newest patch is installed and held |

Instance type (`r8i.large`) and disk size (30 GiB) are set in `compute.tf`.

## Outputs

`amqp_endpoints`, `management_url`, `node_private_ips`, `secret_arn`, `backup_location`.

## TO-DO

- [ ] A user per app, with permissions limited to its own queues
- [ ] Alerts on memory/disk alarms and queue length (Prometheus metrics on :15692)
- [ ] Separate EBS volume for `/var/lib/rabbitmq` if backlogs grow large

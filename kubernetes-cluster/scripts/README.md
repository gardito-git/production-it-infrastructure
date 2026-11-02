# Kubernetes bootstrap scripts

These scripts turn the 12 EC2 instances into a highly available Kubernetes cluster:
**3 external etcd + 3 control plane + 6 workers**, built with `kubeadm`.

You don't run anything by hand. `terraform apply` starts every node, and each node
bootstraps itself at first boot through its user data.

## What's installed

| Component | Version | Why |
|---|---|---|
| Ubuntu | 24.04 LTS | Supported until 2029 |
| Kubernetes (kubeadm, kubelet, kubectl) | `var.kubernetes_version`, default 1.37 | Latest patch from `pkgs.k8s.io`, held with `apt-mark hold` |
| containerd | Ubuntu package | Container runtime, `SystemdCgroup = true` |
| etcd | Whatever kubeadm picks for that Kubernetes version | Runs as a static pod on the etcd nodes |
| Cilium (CNI) | `var.cilium_version`, default 1.20.4 | Pod networking + network policies, VXLAN overlay |

## How the nodes coordinate

The nodes don't need to start in any order. Each one waits for the files it needs
in the private bootstrap S3 bucket:

```
etcd-1 ─ creates etcd CA + certs ─┬─► etcd/<ip>.tar.gz ──────────► etcd-2, etcd-3 start etcd
                                  └─► control-plane/etcd-client ─► control-plane-1
control-plane-1 ─ waits for all 3 etcd ─ kubeadm init ─┬─► join/control-plane.sh ─► control-plane-2, -3
                                                       └─► join/worker.sh ────────► worker-1 … worker-6
control-plane-1 ─ installs Cilium ─► nodes become Ready
```

Expect about 10–15 minutes from `terraform apply` to all nodes `Ready`.

| File | Runs on | What it does |
|---|---|---|
| `user-data.sh.tftpl` | every node | Terraform template: writes `/etc/k8s-bootstrap/env` and these scripts to `/opt/k8s-bootstrap/`, then runs `bootstrap.sh` |
| `bootstrap.sh` | every node | Runs `node-prep.sh`, then the step for this node's role |
| `lib.sh` | (sourced) | Logging, IMDSv2, S3 upload/wait helpers |
| `node-prep.sh` | every node | Swap off, kernel modules, sysctls, containerd, kubelet/kubeadm/kubectl, AWS CLI |
| `etcd-certs.sh` | etcd-1 | etcd CA and per-member certificates |
| `etcd-start.sh` | etcd-1..3 | Installs this member's certs and starts etcd |
| `control-plane-init.sh` | control-plane-1 | `kubeadm init`, publishes join commands, installs Cilium |
| `control-plane-join.sh` | control-plane-2, -3 | `kubeadm join --control-plane` |
| `worker-join.sh` | worker-1..6 | `kubeadm join` |

## Watching the bootstrap

Every node logs to `/var/log/k8s-bootstrap.log`. Open a shell with SSM (no SSH key needed):

```bash
aws ssm start-session --target <instance-id>
sudo tail -f /var/log/k8s-bootstrap.log
```

Then check the cluster from control-plane-1:

```bash
sudo kubectl get nodes -o wide        # 3 control-plane + 6 workers, all Ready
sudo kubectl get pods -A
sudo cilium status
```

The etcd nodes are not Kubernetes nodes, so they don't appear in `kubectl get nodes`.

## kubectl from your laptop

The API is only reachable inside the VPC. Forward it through a control-plane node with SSM:

```bash
aws ssm start-session --target <control-plane-instance-id> \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "host=<kubernetes_api_endpoint>,portNumber=6443,localPortNumber=6443"
```

Copy `/etc/kubernetes/admin.conf` from control-plane-1 to your laptop, change `server:` to
`https://127.0.0.1:6443`, and use it as your kubeconfig. Treat it like a root password.

## After the cluster is up: delete the bootstrap secrets

The bucket holds etcd private keys and join tokens. Objects expire after 1 day anyway,
but delete them as soon as all nodes are `Ready`:

```bash
aws s3 rm "s3://$(terraform output -raw kubernetes_bootstrap_bucket)" --recursive
```

## If something fails

- **A node is stuck "Waiting for s3://…"**: the node that produces that file failed.
  Check its log first (etcd-1 for etcd files, control-plane-1 for join files).
- **Re-running a step**: fix the cause, then `sudo rm -f /var/lib/k8s-bootstrap.done` (if present)
  and `sudo /opt/k8s-bootstrap/bootstrap.sh`. For a failed `kubeadm init`/`join`, run
  `sudo kubeadm reset -f` first.
- **control-plane-2/-3 join after more than 2 hours**: the certificate key has expired. On control-plane-1:
  `sudo kubeadm init phase upload-certs --upload-certs` prints a new key; use it with
  `kubeadm token create --print-join-command` plus `--control-plane --certificate-key <key>`.
- **Script changes don't reach running nodes.** `user_data` is in `ignore_changes`, so edits
  only affect new instances. That's deliberate: Terraform must never replace a cluster node
  just because a script changed.

## Production checklist: what this doesn't do yet

1. **etcd backups.** The most important one. Add a cron or systemd timer on etcd-1
   that runs `etcdctl snapshot save` and uploads to a versioned S3 bucket. Without backups,
   losing 2 of 3 etcd nodes means losing the cluster.
2. **AWS cloud controller manager + EBS CSI driver**, for `type: LoadBalancer` Services and
   PersistentVolumes on EBS. The `kubernetes.io/cluster/<name>` tags are already in place.
3. **Monitoring and logging**, e.g. kube-prometheus-stack plus a log shipper.
4. **Upgrades.** Follow `kubeadm upgrade` one minor version at a time: control plane first,
   then workers. Bump `kubernetes_version` for new nodes at the same time.
5. **Node replacement.** A new worker or control-plane node needs a fresh join command,
   because tokens last 24h. A replaced etcd node keeps its fixed IP, but you must remove
   the old member and add the new one with `etcdctl member` first.
6. **Remote Terraform state** (S3 backend + locking) before more than one person runs `apply`.

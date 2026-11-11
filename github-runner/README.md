# GitHub Actions self-hosted runners on EC2

3 permanent runners (one per AZ) in the private subnets. GitHub stays the "brain" (workflows,
logs, history, approvals); these EC2 instances are the workers that run the jobs, from
inside the VPC.

```
github.com ◄──── HTTPS (outbound only: "any job for me?") ──── runner-1 / runner-2 / runner-3
                                                                (private subnets, via NAT)
                                                                     │
                                       S3, frontend servers, other ◄─┘ jobs reach the VPC
                                       modules, AWS APIs (IAM role)
```

| | |
|---|---|
| Runners | 3 × `c8i.xlarge` (4 vCPU, 8 GiB + 4 GiB swap), Ubuntu 24.04, 100 GiB gp3 |
| Registered at | Your organization (all its repositories can use them) or one repository |
| Labels | `self-hosted`, `linux`, `x64` (automatic) + `aws`, `vpc` |
| Installed | git, Docker (+ buildx, compose), AWS CLI, Ansible + boto3, build-essential, Python 3, jq, zip |
| AWS access | IAM role (no keys in GitHub): read the registration token + `policy_arns` (frontend releases) |
| Inbound | None, except SSH from the VPN. Runners only connect out |

## `ubuntu-24.04` vs `self-hosted`

| `runs-on:` | Runs on | Reaches the VPC | Cost |
|---|---|---|---|
| `ubuntu-24.04` | GitHub's machines, a fresh VM per job | ❌ | GitHub minutes |
| `[self-hosted, vpc]` | **These runners** | ✅ servers, S3, IAM role | These EC2 instances |

Use GitHub's runners for jobs that need nothing private (tests, linting), and these for
anything that deploys or needs the VPC. Both can be in the same workflow.

## One-time setup

1. **Set `github_runner_scope`** in `terraform.tfvars`: your organization (`"my-org"`) or a
   repository (`"my-org/my-repo"`), then `terraform apply`. The runners boot and **wait** for
   step 3 (up to 2 hours; after that, re-run `sudo /opt/github-runner-bootstrap/bootstrap.sh`).
2. **Create a GitHub token** that may register runners. A **fine-grained personal access token**:
   - Organization scope: *Resource owner* = your organization, permission
     **Organization → Self-hosted runners: Read and write**.
   - Repository scope: that repository, permission **Repository → Administration: Read and write**.

   It's used only when a runner registers (each runner then has its own credentials), so a
   short expiry is fine; you need a valid one again only to add or replace a runner.
3. **Put it in Secrets Manager** (never in Terraform code or state):

   ```bash
   aws secretsmanager put-secret-value \
     --secret-id "$(terraform output -raw github_runner_secret_arn)" \
     --secret-string '{"token":"github_pat_..."}'
   ```

   Within a minute the runners register. Check in GitHub: organization (or repository)
   **Settings → Actions → Runners**: `example-dev-runner-1/2/3`, status **Idle**.
4. **Organization only:** in **Settings → Actions → Runner groups → Default**, check which
   repositories may use the group. Keep it to **private** repositories: on a public repository,
   anyone's pull request could run code on your runners, inside your VPC.

## Using them in a workflow

```yaml
jobs:
  test:
    runs-on: ubuntu-24.04            # GitHub's machines: no VPC access needed
    steps:
      - uses: actions/checkout@v5
      - run: npm ci && npm test

  release:
    needs: test
    runs-on: [self-hosted, vpc]      # one of the 3 runners in your VPC
    steps:
      - uses: actions/checkout@v5
      - uses: actions/setup-node@v5  # languages via setup-* actions, cached on the runner
        with:
          node-version: 24
      - run: aws sts get-caller-identity   # AWS access through the IAM role, no secrets
```

**Languages aren't preinstalled** (we don't know them yet): `actions/setup-node`,
`setup-java`, `setup-go`, `setup-python`, `setup-dotnet`... install the version a workflow asks
for and keep it cached on the runner. Docker is there for `docker build` and `container:` jobs.

## Things to know

- **One job per runner at a time.** 3 runners = 3 jobs in parallel; more queue up. Add runners
  with `runner_count`.
- **Permanent runners keep state between jobs** (Docker images, caches, files outside the
  workspace). Faster builds, but a job can see what an earlier job left. Fine for your own
  private repositories; never for untrusted code.
- **Every job gets the runners' IAM permissions.** Add only narrow policies to `policy_arns`, and
  keep it to repositories you trust.
- **Docker access is root-equivalent** on the runner (the `runner` user is in the `docker` group).
  That's why these are dedicated machines.
- **Disk:** a daily timer (03:00 UTC) removes Docker images, build cache and workspaces unused
  for 3 or 14 days. Check with `df -h`; raise the 100 GiB in `compute.tf` if needed.
- **Updates:** the runner updates itself (GitHub requires recent versions). `runner_version` is
  only the first install. Ubuntu packages: `sudo apt upgrade` now and then, or replace the runner.
- **Replacing a runner** (`terraform apply -replace='module.github_runner.aws_instance.runner[0]'`):
  the new instance registers under the same name (`--replace`), as long as the token in Secrets
  Manager is still valid. Remove leftover **Offline** runners in GitHub's runner list.

## Operating

```bash
ssh ubuntu@<runner-ip>                                   # over the VPN
sudo tail -f /var/log/github-runner-bootstrap.log         # first boot
systemctl status 'actions.runner.*'                       # the runner service
sudo journalctl -u 'actions.runner.*' -f                  # live job log
sudo /usr/local/sbin/runner-cleanup                       # free disk now
```

## Files

| File | What's in it |
|---|---|
| `compute.tf` | AMI, key pair, the runners |
| `secret-manager.tf` | Empty secret for the GitHub token (you fill it) |
| `iam.tf` | Role: read the token secret + `policy_arns` |
| `security-groups.tf` | No inbound except SSH from the VPN; all outbound |
| `scripts/node-prep.sh` | Build tools, Docker, AWS CLI, Ansible, swap, daily cleanup |
| `scripts/runner.sh` | Download + checksum, wait for the token, register, start the service |

## Inputs

| Name | Default | Description |
|---|---|---|
| `project_name`, `environment` | (required) | Used in resource and runner names |
| `vpc_id`, `private_subnet_ids` | (required) | Where the runners run |
| `ssh_public_key`, `ssh_source_security_group_id` | (required) | SSH key; the VPN may SSH in |
| `github_scope` | (required) | `"my-org"` or `"my-org/my-repo"` |
| `runner_count` | `3` | One job at a time each |
| `runner_labels` | `["aws", "vpc"]` | Extra labels for `runs-on` |
| `runner_group` | `"Default"` | Organization runner group |
| `runner_version` | `"2.338.2"` | First install; runners update themselves |
| `policy_arns` | `{}` | Extra IAM policies for jobs (root: the frontend deployer policy) |

## Outputs

`secret_arn`, `runner_names`, `private_ips`, `role_name`, `security_group_id`.

## TO-DO

- [ ] Frontend deploy from a runner: allow SSH from the runners' security group to the Next.js
      servers and give jobs the deploy SSH key, so `ansible-playbook deploy.yml` can run in a workflow
- [ ] A GitHub App instead of a personal token (not tied to one person's account)
- [ ] Ephemeral runners (a fresh machine per job) if you ever run less-trusted code

data "aws_ami" "ubuntu_2404" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_region" "current" {}

data "aws_subnet" "private" {
  id = var.private_subnet_id
}

locals {
  # Fixed private IP: .110 in the first private subnet. Agents use it directly,
  # so they work even before DNS is involved.
  private_ip = cidrhost(data.aws_subnet.private.cidr_block, 110)

  # Every *.sh in scripts/ is copied onto the server by user-data.sh.tftpl.
  bootstrap_scripts = {
    for f in fileset("${path.module}/scripts", "*.sh") :
    f => replace(file("${path.module}/scripts/${f}"), "\r\n", "\n")
  }
}

# Your public key, installed for user "ubuntu". Connect to the VPN, then: ssh ubuntu@<private-ip>
resource "aws_key_pair" "monitoring" {
  key_name   = "${local.name_prefix}-monitoring"
  public_key = var.ssh_public_key
}

resource "aws_instance" "monitoring" {
  ami                         = data.aws_ami.ubuntu_2404.id
  instance_type               = "r8i.xlarge" # 4 vCPU, 32 GiB: PMM (VictoriaMetrics, ClickHouse, Grafana), Loki, Prometheus
  subnet_id                   = var.private_subnet_id
  private_ip                  = local.private_ip
  vpc_security_group_ids      = [aws_security_group.monitoring.id]
  iam_instance_profile        = aws_iam_instance_profile.monitoring.name
  key_name                    = aws_key_pair.monitoring.key_name
  associate_public_ip_address = false

  # IMDSv2 only. Hop limit 2: Loki runs in a container (one extra hop) and gets
  # its S3 credentials from the instance role.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  # OS and Docker images; all monitoring data is on aws_ebs_volume.data.
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    encrypted             = true
    delete_on_termination = true
  }

  user_data_base64 = base64gzip(templatefile("${path.module}/scripts/user-data.sh.tftpl", {
    aws_region          = data.aws_region.current.region
    domain_name         = var.domain_name
    environment         = var.environment
    github_organization = coalesce(var.github_organization, "")
    pmm_version         = var.pmm_version
    loki_version        = var.loki_version
    prometheus_version  = var.prometheus_version
    retention_days      = var.retention_days
    loki_bucket         = aws_s3_bucket.loki.id
    data_volume_id      = aws_ebs_volume.data.id
    admin_secret_arn    = aws_secretsmanager_secret.admin.arn
    agent_token_secret  = aws_secretsmanager_secret.agent_token.arn
    github_secret_arn   = aws_secretsmanager_secret.github.arn
    scripts             = local.bootstrap_scripts
  }))

  tags = {
    Name = "${local.name_prefix}-monitoring"
  }

  volume_tags = {
    Name = "${local.name_prefix}-monitoring-root"
  }

  lifecycle {
    ignore_changes = [
      ami,              # A newer Ubuntu AMI must never silently replace the server.
      user_data_base64, # Script edits only apply to a new server.
    ]
  }

  depends_on = [
    aws_iam_role_policy.monitoring,
    aws_secretsmanager_secret_version.admin,
  ]
}

# All monitoring data: PMM (metrics, query analytics, dashboards, users),
# Prometheus (Kubernetes metrics) and Loki's local index cache. Logs are in S3.
resource "aws_ebs_volume" "data" {
  availability_zone = data.aws_subnet.private.availability_zone
  type              = "gp3"
  size              = 100
  encrypted         = true

  tags = {
    Name                 = "${local.name_prefix}-monitoring-data"
    MonitoringDataBackup = local.name_prefix
  }
}

resource "aws_volume_attachment" "data" {
  device_name = "/dev/sdf" # appears as an NVMe device; node-prep.sh finds it by volume ID
  volume_id   = aws_ebs_volume.data.id
  instance_id = aws_instance.monitoring.id

  stop_instance_before_detaching = true
}

# Daily snapshots, so dashboards, users and alert rules survive a lost volume.
resource "aws_dlm_lifecycle_policy" "data" {
  description        = "Daily snapshots of ${local.name_prefix} monitoring data"
  execution_role_arn = aws_iam_role.dlm.arn
  state              = "ENABLED"

  policy_details {
    resource_types = ["VOLUME"]

    schedule {
      name = "daily"

      create_rule {
        interval      = 24
        interval_unit = "HOURS"
        times         = ["04:00"]
      }

      retain_rule {
        count = var.snapshot_retention_count
      }

      copy_tags = true
    }

    target_tags = {
      MonitoringDataBackup = local.name_prefix
    }
  }

  depends_on = [aws_iam_role_policy_attachment.dlm]
}

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

locals {
  # Three identical nodes, one per AZ, on fixed IPs: .80 in each private subnet
  # (.10 etcd, .20 PostgreSQL, .30 Redis, .40-.60 Elasticsearch, .70 Next.js).
  # Apps list all three; a replaced node comes back on the same IP.
  node_ips = [for cidr in var.private_subnet_cidrs : cidrhost(cidr, 80)]

  # Every *.sh in scripts/ is copied onto each node by user-data.sh.tftpl.
  # replace() strips Windows line endings (CRLF), which would break bash on Linux.
  bootstrap_scripts = {
    for f in fileset("${path.module}/scripts", "*.sh") :
    f => replace(file("${path.module}/scripts/${f}"), "\r\n", "\n")
  }

  user_data_vars = {
    aws_region       = data.aws_region.current.region
    cluster_name     = "${local.name_prefix}-rabbitmq"
    node_ips         = join(" ", local.node_ips)
    rabbitmq_version = var.rabbitmq_version
    secret_arn       = aws_secretsmanager_secret.rabbitmq.arn
    backup_bucket    = var.backup_bucket_name
    backup_prefix    = var.backup_prefix
    scripts          = local.bootstrap_scripts
  }
}

# Your public key, installed for user "ubuntu". Connect to the VPN, then: ssh ubuntu@<node-ip>
resource "aws_key_pair" "nodes" {
  key_name   = "${local.name_prefix}-rabbitmq"
  public_key = var.ssh_public_key
}

resource "aws_instance" "rabbitmq" {
  count = 3

  ami                         = data.aws_ami.ubuntu_2404.id
  instance_type               = "r8i.large" # 2 vCPU, 16 GiB: RabbitMQ keeps queues in RAM as a buffer
  subnet_id                   = var.private_subnet_ids[count.index]
  private_ip                  = local.node_ips[count.index]
  vpc_security_group_ids      = [aws_security_group.rabbitmq.id]
  iam_instance_profile        = aws_iam_instance_profile.rabbitmq.name
  key_name                    = aws_key_pair.nodes.key_name
  associate_public_ip_address = false

  # IMDSv2 only.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # OS and RabbitMQ's data (/var/lib/rabbitmq) on one disk. Persistent messages
  # and quorum queue logs are written here; RabbitMQ blocks publishers when
  # free space drops below 5 GB (disk_free_limit in rabbitmq.sh).
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    encrypted             = true
    delete_on_termination = true
  }

  user_data_base64 = base64gzip(templatefile("${path.module}/scripts/user-data.sh.tftpl", merge(local.user_data_vars, {
    node_index = count.index
  })))

  tags = {
    Name = "${local.name_prefix}-rabbitmq-${count.index + 1}"
  }

  volume_tags = {
    Name = "${local.name_prefix}-rabbitmq-${count.index + 1}-root"
  }

  lifecycle {
    ignore_changes = [
      ami,              # A newer Ubuntu AMI must never silently replace a RabbitMQ node.
      user_data_base64, # Script edits only apply to new nodes.
    ]
  }

  # The nodes read the secret at first boot.
  depends_on = [
    aws_iam_role_policy.rabbitmq,
    aws_secretsmanager_secret_version.rabbitmq,
  ]
}

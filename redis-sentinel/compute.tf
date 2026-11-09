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

# Looked up for each subnet's AZ: an EBS volume must be in the same AZ as its instance.
data "aws_subnet" "private" {
  count = length(var.private_subnet_ids)
  id    = var.private_subnet_ids[count.index]
}

locals {
  # Three identical nodes, one per AZ. redis-1 is the master at first start;
  # after that Sentinel decides, so all must be the same size.
  # Fixed IPs (.30 in each private subnet: .10 is etcd, .20 PostgreSQL) let the
  # sentinels and clients list the nodes up front.
  node_ips = [for cidr in var.private_subnet_cidrs : cidrhost(cidr, 30)]

  # Every *.sh in scripts/ is copied onto each node by user-data.sh.tftpl.
  # replace() strips Windows line endings (CRLF), which would break bash on Linux.
  bootstrap_scripts = {
    for f in fileset("${path.module}/scripts", "*.sh") :
    f => replace(file("${path.module}/scripts/${f}"), "\r\n", "\n")
  }

  user_data_vars = {
    aws_region           = data.aws_region.current.region
    node_ips             = join(" ", local.node_ips)
    redis_version        = var.redis_version
    sentinel_master_name = var.sentinel_master_name
    maxmemory_policy     = var.maxmemory_policy
    secret_arn           = aws_secretsmanager_secret.redis.arn
    backup_bucket        = var.backup_bucket_name
    backup_prefix        = var.backup_prefix
    scripts              = local.bootstrap_scripts
  }
}

# Your public key, installed for user "ubuntu". Connect to the VPN, then: ssh ubuntu@<node-ip>
resource "aws_key_pair" "nodes" {
  key_name   = "${local.name_prefix}-redis"
  public_key = var.ssh_public_key
}

resource "aws_instance" "redis" {
  count = 3

  ami                         = data.aws_ami.ubuntu_2404.id
  instance_type               = var.instance_type
  subnet_id                   = var.private_subnet_ids[count.index]
  private_ip                  = local.node_ips[count.index]
  vpc_security_group_ids      = [aws_security_group.redis.id]
  iam_instance_profile        = aws_iam_instance_profile.redis.name
  key_name                    = aws_key_pair.nodes.key_name
  associate_public_ip_address = false

  # IMDSv2 only.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # OS only; Redis data lives on aws_ebs_volume.data.
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    encrypted             = true
    delete_on_termination = true
  }

  user_data_base64 = base64gzip(templatefile("${path.module}/scripts/user-data.sh.tftpl", merge(local.user_data_vars, {
    node_index     = count.index
    data_volume_id = aws_ebs_volume.data[count.index].id
  })))

  tags = {
    Name = "${local.name_prefix}-redis-${count.index + 1}"
  }

  volume_tags = {
    Name = "${local.name_prefix}-redis-${count.index + 1}-root"
  }

  lifecycle {
    ignore_changes = [
      ami,              # A newer Ubuntu AMI must never silently replace a Redis node.
      user_data_base64, # Script edits only apply to new nodes.
    ]
  }

  # The nodes read the secret at first boot.
  depends_on = [
    aws_iam_role_policy.redis,
    aws_secretsmanager_secret_version.redis,
  ]
}

# Separate data volumes for the RDB snapshots and the AOF: sized independently,
# and re-attached if an instance is replaced.
resource "aws_ebs_volume" "data" {
  count = 3

  availability_zone = data.aws_subnet.private[count.index].availability_zone
  type              = "gp3"
  size              = var.data_volume_size
  encrypted         = true

  tags = {
    Name = "${local.name_prefix}-redis-${count.index + 1}-data"
  }
}

resource "aws_volume_attachment" "data" {
  count = 3

  device_name = "/dev/sdf" # appears as an NVMe device; node-prep.sh finds it by volume ID
  volume_id   = aws_ebs_volume.data[count.index].id
  instance_id = aws_instance.redis[count.index].id

  # Stop the instance before detaching, so Redis isn't cut off mid-write.
  stop_instance_before_detaching = true
}

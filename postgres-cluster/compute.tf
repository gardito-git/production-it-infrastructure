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
  ami_id = data.aws_ami.ubuntu_2404.id

  # Three identical nodes, one per AZ. There is no fixed "primary" instance:
  # Patroni elects one, and any node can take over, so all must be the same size.
  # Fixed IPs (.20 in each private subnet) let etcd and Patroni list their
  # peers up front, and a replaced node comes back on the same address.
  node_ips = [for cidr in var.private_subnet_cidrs : cidrhost(cidr, 20)]

  # Every *.sh in scripts/ is copied onto each node by user-data.sh.tftpl.
  # replace() strips Windows line endings (CRLF), which would break bash on Linux.
  bootstrap_scripts = {
    for f in fileset("${path.module}/scripts", "*.sh") :
    f => replace(file("${path.module}/scripts/${f}"), "\r\n", "\n")
  }

  user_data_vars = {
    cluster_name          = "${local.name_prefix}-pg"
    aws_region            = data.aws_region.current.region
    node_ips              = join(" ", local.node_ips)
    vpc_cidr              = var.vpc_cidr
    postgres_version      = var.postgres_version
    etcd_version          = var.etcd_version
    secret_arn            = aws_secretsmanager_secret.postgres.arn
    backup_bucket         = aws_s3_bucket.backups.id
    backup_retention_full = var.backup_retention_full
    scripts               = local.bootstrap_scripts
  }
}

# Your public key, installed for user "ubuntu". Connect to the VPN, then: ssh ubuntu@<node-ip>
resource "aws_key_pair" "nodes" {
  key_name   = "${local.name_prefix}-postgres"
  public_key = var.ssh_public_key
}

resource "aws_instance" "postgres" {
  count = 3

  ami                         = local.ami_id
  instance_type               = var.instance_type
  subnet_id                   = var.private_subnet_ids[count.index]
  private_ip                  = local.node_ips[count.index]
  vpc_security_group_ids      = [aws_security_group.postgres.id]
  iam_instance_profile        = aws_iam_instance_profile.postgres.name
  key_name                    = aws_key_pair.nodes.key_name
  associate_public_ip_address = false

  # IMDSv2 only.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # OS only; the database lives on aws_ebs_volume.data.
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    encrypted             = true
    delete_on_termination = true
  }

  # Gzipped: uncompressed it's ~17 KB, over EC2's 16 KB limit (cloud-init unzips it).
  user_data_base64 = base64gzip(templatefile("${path.module}/scripts/user-data.sh.tftpl", merge(local.user_data_vars, {
    node_index     = count.index
    data_volume_id = aws_ebs_volume.data[count.index].id
  })))

  tags = {
    Name = "${local.name_prefix}-pg-${count.index + 1}"
  }

  volume_tags = {
    Name = "${local.name_prefix}-pg-${count.index + 1}-root"
  }

  lifecycle {
    ignore_changes = [
      ami,              # A newer Ubuntu AMI must never silently replace a database node.
      user_data_base64, # Script edits only apply to new nodes.
    ]
  }

  # The nodes read the secret and write to the bucket at first boot.
  depends_on = [
    aws_iam_role_policy.postgres,
    aws_secretsmanager_secret_version.postgres,
  ]
}

# Separate data volumes: sized independently of the instance, and if an instance
# is replaced, its volume is re-attached instead of the data being copied again.
resource "aws_ebs_volume" "data" {
  count = 3

  availability_zone = data.aws_subnet.private[count.index].availability_zone
  type              = "gp3"
  size              = var.data_volume_size
  iops              = var.data_volume_iops
  throughput        = var.data_volume_throughput
  encrypted         = true

  tags = {
    Name = "${local.name_prefix}-pg-${count.index + 1}-data"
  }
}

resource "aws_volume_attachment" "data" {
  count = 3

  device_name = "/dev/sdf" # appears as an NVMe device; node-prep.sh finds it by volume ID
  volume_id   = aws_ebs_volume.data[count.index].id
  instance_id = aws_instance.postgres[count.index].id

  # Stop the instance before detaching, so PostgreSQL isn't cut off mid-write.
  stop_instance_before_detaching = true
}

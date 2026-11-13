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
  # Three identical members, one per AZ, on fixed IPs: .100 in each private subnet
  # (.10 etcd, .20 PostgreSQL, .30 Redis, .40-.60 Elasticsearch, .70 Next.js, .80 RabbitMQ).
  # The replica set config and every client's connection string list these IPs.
  node_ips = [for cidr in var.private_subnet_cidrs : cidrhost(cidr, 100)]

  # Every *.sh in scripts/ is copied onto each node by user-data.sh.tftpl.
  # replace() strips Windows line endings (CRLF), which would break bash on Linux.
  bootstrap_scripts = {
    for f in fileset("${path.module}/scripts", "*.sh") :
    f => replace(file("${path.module}/scripts/${f}"), "\r\n", "\n")
  }

  user_data_vars = {
    aws_region       = data.aws_region.current.region
    node_ips         = join(" ", local.node_ips)
    mongodb_version  = var.mongodb_version
    replica_set_name = var.replica_set_name
    secret_arn       = aws_secretsmanager_secret.mongodb.arn
    backup_bucket    = var.backup_bucket_name
    backup_prefix    = var.backup_prefix
    scripts          = local.bootstrap_scripts
  }
}

# Your public key, installed for user "ubuntu". Connect to the VPN, then: ssh ubuntu@<node-ip>
resource "aws_key_pair" "nodes" {
  key_name   = "${local.name_prefix}-mongodb"
  public_key = var.ssh_public_key
}

resource "aws_instance" "mongodb" {
  count = 3

  ami                         = data.aws_ami.ubuntu_2404.id
  instance_type               = "r8i.large" # 2 vCPU, 16 GiB: WiredTiger's cache is about half the RAM
  subnet_id                   = var.private_subnet_ids[count.index]
  private_ip                  = local.node_ips[count.index]
  vpc_security_group_ids      = [aws_security_group.mongodb.id]
  iam_instance_profile        = aws_iam_instance_profile.mongodb.name
  key_name                    = aws_key_pair.nodes.key_name
  associate_public_ip_address = false

  # IMDSv2 only.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # OS only; MongoDB's data lives on aws_ebs_volume.data.
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
    Name = "${local.name_prefix}-mongodb-${count.index + 1}"
  }

  volume_tags = {
    Name = "${local.name_prefix}-mongodb-${count.index + 1}-root"
  }

  lifecycle {
    ignore_changes = [
      ami,              # A newer Ubuntu AMI must never silently replace a member.
      user_data_base64, # Script edits only apply to new nodes.
    ]
  }

  # The nodes read the secret at first boot.
  depends_on = [
    aws_iam_role_policy.mongodb,
    aws_secretsmanager_secret_version.mongodb,
  ]
}

# Separate data volumes (/var/lib/mongodb): sized independently of the OS, and
# re-attached if an instance is replaced.
resource "aws_ebs_volume" "data" {
  count = 3

  availability_zone = data.aws_subnet.private[count.index].availability_zone
  type              = "gp3"
  size              = 100
  encrypted         = true

  tags = {
    Name = "${local.name_prefix}-mongodb-${count.index + 1}-data"
  }
}

resource "aws_volume_attachment" "data" {
  count = 3

  device_name = "/dev/sdf" # appears as an NVMe device; node-prep.sh finds it by volume ID
  volume_id   = aws_ebs_volume.data[count.index].id
  instance_id = aws_instance.mongodb[count.index].id

  # Stop the instance before detaching, so MongoDB isn't cut off mid-write.
  stop_instance_before_detaching = true
}

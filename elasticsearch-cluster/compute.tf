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
  subnet_count = length(var.private_subnet_ids)

  # Fixed IPs, so nodes and clients find each other without DNS:
  #   masters .40 (one per AZ), data nodes .50, .51, ... (round-robin over the AZs), Kibana .60 (AZ a)
  # Other modules use .10 (etcd), .20 (PostgreSQL), .30 (Redis).
  master_ips = [for cidr in var.private_subnet_cidrs : cidrhost(cidr, 40)]
  data_ips = [
    for i in range(var.data_node_count) :
    cidrhost(var.private_subnet_cidrs[i % local.subnet_count], 50 + floor(i / local.subnet_count))
  ]
  kibana_ip = cidrhost(var.private_subnet_cidrs[0], 60)

  # Every *.sh in scripts/ is copied onto each node by user-data.sh.tftpl.
  # replace() strips Windows line endings (CRLF), which would break bash on Linux.
  bootstrap_scripts = {
    for f in fileset("${path.module}/scripts", "*.sh") :
    f => replace(file("${path.module}/scripts/${f}"), "\r\n", "\n")
  }

  user_data_vars = {
    cluster_name    = "${local.name_prefix}-es"
    aws_region      = data.aws_region.current.region
    elastic_version = var.elastic_version
    master_ips      = join(" ", local.master_ips)
    data_ips        = join(" ", local.data_ips)
    secret_arn      = aws_secretsmanager_secret.elasticsearch.arn
    backup_bucket   = var.backup_bucket_name
    backup_prefix   = var.backup_prefix
    scripts         = local.bootstrap_scripts
  }
}

# Your public key, installed for user "ubuntu". Connect to the VPN, then: ssh ubuntu@<node-ip>
resource "aws_key_pair" "nodes" {
  key_name   = "${local.name_prefix}-elasticsearch"
  public_key = var.ssh_public_key
}

# Master nodes: one per AZ. They only manage the cluster, so they stay
# responsive even when the data nodes are busy.
resource "aws_instance" "master" {
  count = 3

  ami                         = data.aws_ami.ubuntu_2404.id
  instance_type               = var.master_instance_type
  subnet_id                   = var.private_subnet_ids[count.index]
  private_ip                  = local.master_ips[count.index]
  vpc_security_group_ids      = [aws_security_group.elasticsearch.id]
  iam_instance_profile        = aws_iam_instance_profile.node["elasticsearch"].name
  key_name                    = aws_key_pair.nodes.key_name
  associate_public_ip_address = false

  # IMDSv2 only.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # Masters keep only the cluster state, which fits on the root volume.
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    encrypted             = true
    delete_on_termination = true
  }

  # Gzipped: cloud-init unzips it, and it keeps the scripts well under EC2's 16 KB limit.
  user_data_base64 = base64gzip(templatefile("${path.module}/scripts/user-data.sh.tftpl", merge(local.user_data_vars, {
    node_role      = "master"
    heap_size      = var.master_heap_size
    node_name      = "es-master-${count.index + 1}"
    data_volume_id = ""
  })))

  tags = {
    Name = "${local.name_prefix}-es-master-${count.index + 1}"
  }

  volume_tags = {
    Name = "${local.name_prefix}-es-master-${count.index + 1}-root"
  }

  lifecycle {
    ignore_changes = [ami, user_data_base64] # never replace a running node for a newer AMI or script edit
  }

  depends_on = [
    aws_iam_role_policy.read_secret,
    aws_iam_role_policy.snapshots,
    aws_secretsmanager_secret_version.elasticsearch,
  ]
}

# Data nodes: hold the indices. Spread round-robin, so each AZ has the same number.
resource "aws_instance" "data" {
  count = var.data_node_count

  ami                         = data.aws_ami.ubuntu_2404.id
  instance_type               = var.data_instance_type
  subnet_id                   = var.private_subnet_ids[count.index % local.subnet_count]
  private_ip                  = local.data_ips[count.index]
  vpc_security_group_ids      = [aws_security_group.elasticsearch.id]
  iam_instance_profile        = aws_iam_instance_profile.node["elasticsearch"].name
  key_name                    = aws_key_pair.nodes.key_name
  associate_public_ip_address = false

  # IMDSv2 only.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # OS only; the indices live on aws_ebs_volume.data.
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    encrypted             = true
    delete_on_termination = true
  }

  user_data_base64 = base64gzip(templatefile("${path.module}/scripts/user-data.sh.tftpl", merge(local.user_data_vars, {
    node_role      = "data"
    heap_size      = var.data_heap_size
    node_name      = "es-data-${count.index + 1}"
    data_volume_id = aws_ebs_volume.data[count.index].id
  })))

  tags = {
    Name = "${local.name_prefix}-es-data-${count.index + 1}"
  }

  volume_tags = {
    Name = "${local.name_prefix}-es-data-${count.index + 1}-root"
  }

  lifecycle {
    ignore_changes = [ami, user_data_base64]
  }

  depends_on = [
    aws_iam_role_policy.read_secret,
    aws_iam_role_policy.snapshots,
    aws_secretsmanager_secret_version.elasticsearch,
  ]
}

# One 100 GiB gp3 volume per data node, re-attached if an instance is replaced.
resource "aws_ebs_volume" "data" {
  count = var.data_node_count

  availability_zone = data.aws_subnet.private[count.index % local.subnet_count].availability_zone
  type              = "gp3"
  size              = var.data_volume_size
  encrypted         = true

  tags = {
    Name = "${local.name_prefix}-es-data-${count.index + 1}-data"
  }
}

resource "aws_volume_attachment" "data" {
  count = var.data_node_count

  device_name = "/dev/sdf" # appears as an NVMe device; elasticsearch.sh finds it by volume ID
  volume_id   = aws_ebs_volume.data[count.index].id
  instance_id = aws_instance.data[count.index].id

  # Stop the instance before detaching, so Elasticsearch isn't cut off mid-write.
  stop_instance_before_detaching = true
}

# Kibana: the web UI for developers, reachable only over the VPN.
resource "aws_instance" "kibana" {
  ami                         = data.aws_ami.ubuntu_2404.id
  instance_type               = var.kibana_instance_type
  subnet_id                   = var.private_subnet_ids[0]
  private_ip                  = local.kibana_ip
  vpc_security_group_ids      = [aws_security_group.kibana.id]
  iam_instance_profile        = aws_iam_instance_profile.node["kibana"].name
  key_name                    = aws_key_pair.nodes.key_name
  associate_public_ip_address = false

  # IMDSv2 only.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    encrypted             = true
    delete_on_termination = true
  }

  user_data_base64 = base64gzip(templatefile("${path.module}/scripts/user-data.sh.tftpl", merge(local.user_data_vars, {
    node_role      = "kibana"
    heap_size      = "" # Kibana is Node.js, not a JVM
    node_name      = "kibana"
    data_volume_id = ""
  })))

  tags = {
    Name = "${local.name_prefix}-kibana"
  }

  volume_tags = {
    Name = "${local.name_prefix}-kibana-root"
  }

  lifecycle {
    ignore_changes = [ami, user_data_base64]
  }

  depends_on = [
    aws_iam_role_policy.read_secret,
    aws_secretsmanager_secret_version.elasticsearch,
  ]
}

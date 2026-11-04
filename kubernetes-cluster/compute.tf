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
  ami_id = data.aws_ami.ubuntu_2404.id

  cluster_tag = {
    "kubernetes.io/cluster/${var.project_name}" = "owned"
  }

  # etcd members get fixed IPs (.10 in each private subnet) so every node's
  # config can list them up front, and a replaced etcd node keeps its address.
  etcd_ips = [
    for i in range(3) :
    cidrhost(var.private_subnet_cidrs[i % length(var.private_subnet_cidrs)], 10 + floor(i / length(var.private_subnet_cidrs)))
  ]

  # Every *.sh in scripts/ is copied onto each node by user-data.sh.tftpl.
  # replace() strips Windows line endings (CRLF), which would break bash on Linux.
  bootstrap_scripts = {
    for f in fileset("${path.module}/scripts", "*.sh") :
    f => replace(file("${path.module}/scripts/${f}"), "\r\n", "\n")
  }

  # Settings shared by every node; node_role and node_index are added per instance.
  user_data_vars = {
    cluster_name           = var.project_name
    aws_region             = data.aws_region.current.region
    bootstrap_bucket       = aws_s3_bucket.bootstrap.id
    kubernetes_version     = var.kubernetes_version
    control_plane_endpoint = aws_lb.api.dns_name
    etcd_ips               = join(" ", local.etcd_ips)
    pod_cidr               = var.pod_cidr
    service_cidr           = var.service_cidr
    cilium_version         = var.cilium_version
    cilium_cli_version     = var.cilium_cli_version
    backup_bucket          = var.backup_bucket_name
    backup_prefix          = var.backup_prefix
    etcd_backup_schedule   = var.etcd_backup_schedule
    scripts                = local.bootstrap_scripts
  }
}

# Your public key, installed for user "ubuntu" on every node.
# Connect to the VPN, then: ssh ubuntu@<private-ip>
resource "aws_key_pair" "nodes" {
  key_name   = "${local.name_prefix}-nodes"
  public_key = var.ssh_public_key
}

# The nodes bootstrap themselves at first boot (see scripts/README.md):
#   etcd-1 creates certs -> etcd-2/3 start -> control-plane-1 runs kubeadm init
#   -> control-plane-2/3 and the workers join.
# They wait for each other through the S3 bucket, so Terraform can start them all at once.
# user_data is gzipped: uncompressed it's ~18 KB, over EC2's 16 KB limit (cloud-init unzips it).

resource "aws_instance" "control_plane" {
  count = 3

  ami                         = local.ami_id
  instance_type               = "c8i.xlarge"
  subnet_id                   = var.private_subnet_ids[count.index % length(var.private_subnet_ids)] # one per AZ, round-robin
  vpc_security_group_ids      = [aws_security_group.control_plane.id]
  iam_instance_profile        = aws_iam_instance_profile.node["control-plane"].name
  key_name                    = aws_key_pair.nodes.key_name
  associate_public_ip_address = false

  # IMDSv2 only; hop limit 1 keeps pods from reaching the metadata service.
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
    node_role  = "control-plane"
    node_index = count.index
  })))

  tags = merge(local.cluster_tag, {
    Name = "${local.name_prefix}-control-plane-${count.index + 1}"
  })

  volume_tags = {
    Name = "${local.name_prefix}-control-plane-${count.index + 1}-root"
  }

  lifecycle {
    ignore_changes = [
      ami,              # A newer Ubuntu AMI must never silently replace a running cluster node.
      user_data_base64, # Script edits only apply to new nodes; never replace running ones.
    ]
  }

  depends_on = [aws_iam_role_policy.bootstrap_access]
}

resource "aws_instance" "worker" {
  count = 6 # Yes, 6. Don't ask me why. It's a long story.

  ami                         = local.ami_id
  instance_type               = "r8i.xlarge"
  subnet_id                   = var.private_subnet_ids[count.index % length(var.private_subnet_ids)] # one per AZ, round-robin
  vpc_security_group_ids      = [aws_security_group.worker.id]
  iam_instance_profile        = aws_iam_instance_profile.node["worker"].name
  key_name                    = aws_key_pair.nodes.key_name
  associate_public_ip_address = false

  # IMDSv2 only; hop limit 1 keeps pods from reaching the metadata service.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 100
    encrypted             = true
    delete_on_termination = true
  }

  user_data_base64 = base64gzip(templatefile("${path.module}/scripts/user-data.sh.tftpl", merge(local.user_data_vars, {
    node_role  = "worker"
    node_index = count.index
  })))

  tags = merge(local.cluster_tag, {
    Name = "${local.name_prefix}-worker-${count.index + 1}"
  })

  volume_tags = {
    Name = "${local.name_prefix}-worker-${count.index + 1}-root"
  }

  lifecycle {
    ignore_changes = [
      ami,              # A newer Ubuntu AMI must never silently replace a running cluster node.
      user_data_base64, # Script edits only apply to new nodes; never replace running ones.
    ]
  }

  depends_on = [aws_iam_role_policy.bootstrap_access]
}

resource "aws_instance" "etcd" {
  count = 3

  ami                         = local.ami_id
  instance_type               = "c8i.large"
  subnet_id                   = var.private_subnet_ids[count.index % length(var.private_subnet_ids)] # one per AZ, round-robin
  private_ip                  = local.etcd_ips[count.index]
  vpc_security_group_ids      = [aws_security_group.etcd.id]
  iam_instance_profile        = aws_iam_instance_profile.node["etcd"].name
  key_name                    = aws_key_pair.nodes.key_name
  associate_public_ip_address = false

  # IMDSv2 only; hop limit 1 keeps pods from reaching the metadata service.
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
    node_role  = "etcd"
    node_index = count.index
  })))

  tags = merge(local.cluster_tag, {
    Name = "${local.name_prefix}-etcd-${count.index + 1}"
  })

  volume_tags = {
    Name = "${local.name_prefix}-etcd-${count.index + 1}-root"
  }

  lifecycle {
    ignore_changes = [
      ami,              # A newer Ubuntu AMI must never silently replace a running cluster node.
      user_data_base64, # Script edits only apply to new nodes; never replace running ones.
    ]
  }

  depends_on = [aws_iam_role_policy.bootstrap_access]
}

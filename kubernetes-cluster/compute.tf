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

locals {
  ami_id = data.aws_ami.ubuntu_2404.id

  cluster_tag = {
    "kubernetes.io/cluster/${var.project_name}" = "owned"
  }

  # Placeholder: cloud-init ignores user data that doesn't start with
  # "#!" (a script) or "#cloud-config", so these steps don't run yet.
  node_user_data = <<-EOT
    # install cloud-init and set hostname
    # install kubelet, kubeadm, kubectl
    # install containerd
    # install CNI plugins
    # configure kubelet to use containerd
  EOT
}

resource "aws_instance" "control_plane" {
  count = 3

  ami                         = local.ami_id
  instance_type               = "c8i.xlarge"
  subnet_id                   = var.private_subnet_ids[count.index % length(var.private_subnet_ids)] # one per AZ, round-robin
  vpc_security_group_ids      = [aws_security_group.control_plane.id]
  iam_instance_profile        = var.instance_profile_name
  key_name                    = var.key_name
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

  user_data = local.node_user_data

  tags = merge(local.cluster_tag, {
    Name = "${local.name_prefix}-control-plane-${count.index + 1}"
  })

  volume_tags = {
    Name = "${local.name_prefix}-control-plane-${count.index + 1}-root"
  }

  lifecycle {
    ignore_changes = [
      ami, # A newer Ubuntu AMI must never silently replace a running cluster node.
      user_data,
    ]
  }
}

resource "aws_instance" "worker" {
  count = 6 # Yes, 6. Don't ask me why. It's a long story.

  ami                         = local.ami_id
  instance_type               = "r8i.xlarge"
  subnet_id                   = var.private_subnet_ids[count.index % length(var.private_subnet_ids)] # one per AZ, round-robin
  vpc_security_group_ids      = [aws_security_group.worker.id]
  iam_instance_profile        = var.instance_profile_name
  key_name                    = var.key_name
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

  user_data = local.node_user_data

  tags = merge(local.cluster_tag, {
    Name = "${local.name_prefix}-worker-${count.index + 1}"
  })

  volume_tags = {
    Name = "${local.name_prefix}-worker-${count.index + 1}-root"
  }

  lifecycle {
    ignore_changes = [
      ami, # A newer Ubuntu AMI must never silently replace a running cluster node.
      user_data,
    ]
  }
}

resource "aws_instance" "etcd" {
  count = 3

  ami                         = local.ami_id
  instance_type               = "c8i.large"
  subnet_id                   = var.private_subnet_ids[count.index % length(var.private_subnet_ids)] # one per AZ, round-robin
  vpc_security_group_ids      = [aws_security_group.etcd.id]
  iam_instance_profile        = var.instance_profile_name
  key_name                    = var.key_name
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

  user_data = local.node_user_data

  tags = merge(local.cluster_tag, {
    Name = "${local.name_prefix}-etcd-${count.index + 1}"
  })

  volume_tags = {
    Name = "${local.name_prefix}-etcd-${count.index + 1}-root"
  }

  lifecycle {
    ignore_changes = [
      ami, # A newer Ubuntu AMI must never silently replace a running cluster node.
      user_data,
    ]
  }
}

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

# Your public key, installed for user "ubuntu". Connect to the VPN, then: ssh ubuntu@<private-ip>
resource "aws_key_pair" "frontend" {
  key_name   = "${local.name_prefix}-frontend"
  public_key = var.ssh_public_key
}

# Fixed servers, not an Auto Scaling group: you deploy to them one by one over
# SSH (deploy-frontend). A server that is replaced deploys releases/CURRENT by
# itself at first boot, so it comes up with the live version.
resource "aws_instance" "frontend" {
  count = var.instance_count

  ami                         = data.aws_ami.ubuntu_2404.id
  instance_type               = "r8i.xlarge" # 4 vCPU, 32 GiB RAM: 3 PM2 processes x 4 GiB (pm2_instances, max_memory_restart_mb)
  subnet_id                   = var.private_subnet_ids[count.index % length(var.private_subnet_ids)] # one per AZ
  vpc_security_group_ids      = [aws_security_group.frontend.id]
  key_name                    = aws_key_pair.frontend.key_name
  iam_instance_profile        = aws_iam_instance_profile.frontend.name
  associate_public_ip_address = false

  # IMDSv2 only; hop limit 1 keeps the role's credentials on the host.
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

  # replace() strips Windows line endings (CRLF), which would break bash on Linux.
  user_data = replace(templatefile("${path.module}/scripts/bootstrap.sh.tftpl", {
    region                = data.aws_region.current.region
    bucket_name           = aws_s3_bucket.frontend.id
    node_major            = 24 # Please adjust for your need.
    pm2_version           = var.pm2_version
    app_port              = var.app_port
    health_check_path     = var.health_check_path
    pm2_instances         = 3 # Becareful of this. Check your instance type.
    node_heap_mb          = var.node_heap_mb
    max_memory_restart_mb = var.max_memory_restart_mb
  }), "\r\n", "\n")

  tags = {
    Name = "${local.name_prefix}-frontend-${count.index + 1}"
    Role = "nextjs-frontend" # Ansible finds the servers by this tag (ansible/inventory.aws_ec2.yml)
  }

  volume_tags = {
    Name = "${local.name_prefix}-frontend-${count.index + 1}-root"
  }

  lifecycle {
    precondition {
      condition     = var.max_memory_restart_mb > var.node_heap_mb
      error_message = "max_memory_restart_mb must be larger than node_heap_mb: a process's RSS is its heap plus buffers and native memory."
    }

    ignore_changes = [
      ami,       # A newer Ubuntu AMI must never silently replace a running server.
      user_data, # Script edits only apply to new servers.
    ]
  }
}

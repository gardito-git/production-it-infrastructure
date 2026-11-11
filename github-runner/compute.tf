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
  # Every *.sh in scripts/ is copied onto each runner by user-data.sh.tftpl.
  # replace() strips Windows line endings (CRLF), which would break bash on Linux.
  bootstrap_scripts = {
    for f in fileset("${path.module}/scripts", "*.sh") :
    f => replace(file("${path.module}/scripts/${f}"), "\r\n", "\n")
  }
}

# Your public key, installed for user "ubuntu". Connect to the VPN, then: ssh ubuntu@<private-ip>
resource "aws_key_pair" "runner" {
  key_name   = "${local.name_prefix}-github-runner"
  public_key = var.ssh_public_key
}

# Permanent runners: each registers once at first boot and then keeps taking
# jobs. A replaced instance registers again under the same name (--replace).
resource "aws_instance" "runner" {
  count = var.runner_count

  ami                         = data.aws_ami.ubuntu_2404.id
  instance_type               = "c8i.xlarge"                                                         # 4 vCPU, 8 GiB: builds are CPU-heavy (npm, Maven, Go, Docker images)
  subnet_id                   = var.private_subnet_ids[count.index % length(var.private_subnet_ids)] # one per AZ
  vpc_security_group_ids      = [aws_security_group.runner.id]
  iam_instance_profile        = aws_iam_instance_profile.runner.name
  key_name                    = aws_key_pair.runner.key_name
  associate_public_ip_address = false

  # IMDSv2 only. Hop limit 2 lets Docker containers in a job use the role too
  # (one extra network hop through the Docker bridge); with 1 only the host can.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  # Room for Docker images, dependency caches and build workspaces; cleaned
  # daily by the runner-cleanup timer.
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 100
    encrypted             = true
    delete_on_termination = true
  }

  user_data_base64 = base64gzip(templatefile("${path.module}/scripts/user-data.sh.tftpl", {
    aws_region     = data.aws_region.current.region
    runner_name    = "${local.name_prefix}-runner-${count.index + 1}"
    github_scope   = var.github_scope
    runner_labels  = join(",", var.runner_labels)
    runner_group   = var.runner_group
    runner_version = var.runner_version
    secret_arn     = aws_secretsmanager_secret.github.arn
    scripts        = local.bootstrap_scripts
  }))

  tags = {
    Name = "${local.name_prefix}-runner-${count.index + 1}"
  }

  volume_tags = {
    Name = "${local.name_prefix}-runner-${count.index + 1}-root"
  }

  lifecycle {
    ignore_changes = [
      ami,              # A newer Ubuntu AMI must never silently replace a runner.
      user_data_base64, # Script edits only apply to new runners.
    ]
  }

  depends_on = [aws_iam_role_policy.runner]
}

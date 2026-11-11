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

# The subnet's CIDR gives the fixed private IP; its AZ places the data volume.
data "aws_subnet" "public" {
  id = var.public_subnet_id
}

locals {
  # Fixed private IP: .90 in the public subnet. The private DNS zone points at it.
  private_ip = cidrhost(data.aws_subnet.public.cidr_block, 90)

  # Every *.sh in scripts/ is copied onto the server by user-data.sh.tftpl.
  # replace() strips Windows line endings (CRLF), which would break bash on Linux.
  bootstrap_scripts = {
    for f in fileset("${path.module}/scripts", "*.sh") :
    f => replace(file("${path.module}/scripts/${f}"), "\r\n", "\n")
  }
}

# Your public key, installed for user "ubuntu". Connect to the VPN, then: ssh ubuntu@<private-ip>
resource "aws_key_pair" "harbor" {
  key_name   = "${local.name_prefix}-harbor"
  public_key = var.ssh_public_key
}

# The public address. It survives replacing the instance, so your DNS record
# never has to change.
resource "aws_eip" "harbor" {
  domain = "vpc"

  tags = {
    Name = "${local.name_prefix}-harbor"
  }
}

resource "aws_eip_association" "harbor" {
  allocation_id = aws_eip.harbor.id
  instance_id   = aws_instance.harbor.id
}

resource "aws_instance" "harbor" {
  ami                         = data.aws_ami.ubuntu_2404.id
  instance_type               = "m8i.xlarge" # 4 vCPU, 16 GiB: Harbor's services plus Trivy scans
  subnet_id                   = var.public_subnet_id
  private_ip                  = local.private_ip
  vpc_security_group_ids      = [aws_security_group.harbor.id]
  iam_instance_profile        = aws_iam_instance_profile.harbor.name
  key_name                    = aws_key_pair.harbor.key_name
  associate_public_ip_address = true # internet access during boot, until the EIP replaces it

  # IMDSv2 only. Hop limit 2 is needed: Harbor's registry runs in a container
  # (one extra network hop) and gets its S3 credentials from the IAM role.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  # OS and Docker images; Harbor's data is on aws_ebs_volume.data.
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    encrypted             = true
    delete_on_termination = true
  }

  user_data_base64 = base64gzip(templatefile("${path.module}/scripts/user-data.sh.tftpl", {
    aws_region              = data.aws_region.current.region
    domain_name             = var.domain_name
    public_ip               = aws_eip.harbor.public_ip
    vpc_cidr                = var.vpc_cidr
    harbor_version          = var.harbor_version
    harbor_installer_sha256 = var.harbor_installer_sha256
    s3_bucket               = aws_s3_bucket.harbor.id
    data_volume_id          = aws_ebs_volume.data.id
    secret_arn              = aws_secretsmanager_secret.harbor.arn
    scripts                 = local.bootstrap_scripts
  }))

  tags = {
    Name = "${local.name_prefix}-harbor"
  }

  volume_tags = {
    Name = "${local.name_prefix}-harbor-root"
  }

  lifecycle {
    ignore_changes = [
      ami,              # A newer Ubuntu AMI must never silently replace Harbor.
      user_data_base64, # Script edits only apply to a new server.
    ]
  }

  # The server reads the secret and uses the bucket at first boot.
  depends_on = [
    aws_iam_role_policy.harbor,
    aws_secretsmanager_secret_version.harbor,
    aws_s3_bucket_policy.harbor,
  ]
}

# Harbor's state: PostgreSQL (users, projects, tags), Redis, encryption keys,
# Trivy's database and the Let's Encrypt certificate. A separate volume, so it
# survives replacing the instance.
resource "aws_ebs_volume" "data" {
  availability_zone = data.aws_subnet.public.availability_zone
  type              = "gp3"
  size              = 100
  encrypted         = true

  tags = {
    Name             = "${local.name_prefix}-harbor-data"
    HarborDataBackup = local.name_prefix
  }
}

resource "aws_volume_attachment" "data" {
  device_name = "/dev/sdf" # appears as an NVMe device; node-prep.sh finds it by volume ID
  volume_id   = aws_ebs_volume.data.id
  instance_id = aws_instance.harbor.id

  # Stop the instance before detaching, so PostgreSQL isn't cut off mid-write.
  stop_instance_before_detaching = true
}

# Daily snapshots of the data volume. Without this data, the images in S3 can't
# be used: S3 has the layers, but only PostgreSQL knows which image is which.
resource "aws_dlm_lifecycle_policy" "data" {
  description        = "Daily snapshots of ${local.name_prefix} Harbor data"
  execution_role_arn = aws_iam_role.dlm.arn
  state              = "ENABLED"

  policy_details {
    resource_types = ["VOLUME"]

    schedule {
      name = "daily"

      create_rule {
        interval      = 24
        interval_unit = "HOURS"
        times         = ["03:30"]
      }

      retain_rule {
        count = var.snapshot_retention_count
      }

      copy_tags = true
    }

    target_tags = {
      HarborDataBackup = local.name_prefix
    }
  }

  depends_on = [aws_iam_role_policy_attachment.dlm]
}

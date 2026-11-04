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
}

resource "aws_instance" "postgres_primary" {
  count         = 1
  ami           = local.ami_id
  instance_type = "r8i.2xlarge"
  subnet_id     = var.private_subnet_ids[count.index % length(var.private_subnet_ids)]
  key_name      = aws_key_pair.nodes.key_name

  vpc_security_group_ids = [aws_security_group.postgres.id]

  user_data = {
    # TO-DO: Add user data script to configure Postgres on the instance
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-postgres-db"
  }
}

resource "aws_instance" "postgres_replica" {
  count         = 2
  ami           = local.ami_id
  instance_type = "r8i.xlarge"
  subnet_id     = var.private_subnet_ids[count.index % length(var.private_subnet_ids)]
  key_name      = aws_key_pair.nodes.key_name

  vpc_security_group_ids = [aws_security_group.postgres.id]

  user_data = {
    # TO-DO: Add user data script to configure Postgres replica on the instance
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-postgres-replica-${count.index + 1}"
  }
}
locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

resource "aws_security_group" "postgres" {
  name        = "${locals.name_prefix}-postgres-db-sg"
  vpc_id      = var.vpc_id
  description = "Security group for Postgres database"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    self        = true
    description = "Allow Postgres traffic from within the security group"
  }

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Allow Postgres traffic from the VPC"
  }
}
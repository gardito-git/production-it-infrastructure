locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# Every rule is its own resource, as in the other modules.
resource "aws_security_group" "mongodb" {
  name        = "${local.name_prefix}-mongodb"
  description = "MongoDB replica set members"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${local.name_prefix}-mongodb"
  }
}

resource "aws_vpc_security_group_egress_rule" "mongodb_all" {
  security_group_id = aws_security_group.mongodb.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "All outbound (packages, S3 backups, Secrets Manager)"
}

# Apps (Kubernetes pods leave from their node's IP), VPN users, and replication
# between the members all use 27017. Login is required (SCRAM), and members
# prove they belong with the shared keyfile.
resource "aws_vpc_security_group_ingress_rule" "mongodb_from_vpc" {
  security_group_id = aws_security_group.mongodb.id
  ip_protocol       = "tcp"
  from_port         = 27017
  to_port           = 27017
  cidr_ipv4         = var.vpc_cidr
  description       = "MongoDB from the VPC"
}

resource "aws_vpc_security_group_ingress_rule" "mongodb_ssh_from_vpn" {
  security_group_id            = aws_security_group.mongodb.id
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = var.ssh_source_security_group_id
  description                  = "SSH from VPN clients"
}

resource "aws_vpc_security_group_ingress_rule" "mongodb_icmp_from_vpc" {
  security_group_id = aws_security_group.mongodb.id
  ip_protocol       = "icmp"
  from_port         = -1
  to_port           = -1
  cidr_ipv4         = var.vpc_cidr
  description       = "ICMP from the VPC"
}

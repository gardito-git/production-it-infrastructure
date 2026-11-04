locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# Every rule is its own resource, as in kubernetes-cluster/security-groups.tf.
resource "aws_security_group" "postgres" {
  name        = "${local.name_prefix}-postgres"
  description = "PostgreSQL cluster nodes (Patroni + etcd)"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${local.name_prefix}-postgres"
  }
}

resource "aws_vpc_security_group_egress_rule" "postgres_all" {
  security_group_id = aws_security_group.postgres.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "All outbound (packages, S3 backups, Secrets Manager)"
}

# Clients go through the NLB with their own IP preserved, so allow the VPC:
# Kubernetes pods/nodes, VPN users, and replication between the nodes.
resource "aws_vpc_security_group_ingress_rule" "postgres_from_vpc" {
  security_group_id = aws_security_group.postgres.id
  ip_protocol       = "tcp"
  from_port         = 5432
  to_port           = 5432
  cidr_ipv4         = var.vpc_cidr
  description       = "PostgreSQL from the VPC (clients via the NLB, replication)"
}

# The NLB health checks call Patroni's /primary and /replica to find out which
# node is which. patronictl on the nodes also talks to each other here.
resource "aws_vpc_security_group_ingress_rule" "patroni_api_from_vpc" {
  security_group_id = aws_security_group.postgres.id
  ip_protocol       = "tcp"
  from_port         = 8008
  to_port           = 8008
  cidr_ipv4         = var.vpc_cidr
  description       = "Patroni REST API (NLB health checks, patronictl)"
}

resource "aws_vpc_security_group_ingress_rule" "etcd_self" {
  security_group_id            = aws_security_group.postgres.id
  ip_protocol                  = "tcp"
  from_port                    = 2379
  to_port                      = 2380
  referenced_security_group_id = aws_security_group.postgres.id
  description                  = "etcd client and peer traffic, between the nodes only"
}

resource "aws_vpc_security_group_ingress_rule" "ssh_from_vpn" {
  security_group_id            = aws_security_group.postgres.id
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = var.ssh_source_security_group_id
  description                  = "SSH from VPN clients"
}

resource "aws_vpc_security_group_ingress_rule" "icmp_from_vpc" {
  security_group_id = aws_security_group.postgres.id
  ip_protocol       = "icmp"
  from_port         = -1
  to_port           = -1
  cidr_ipv4         = var.vpc_cidr
  description       = "ICMP from the VPC"
}

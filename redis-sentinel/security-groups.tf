locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# Every rule is its own resource, as in the other modules.
resource "aws_security_group" "redis" {
  name        = "${local.name_prefix}-redis"
  description = "Redis + Sentinel nodes"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${local.name_prefix}-redis"
  }
}

resource "aws_vpc_security_group_egress_rule" "redis_all" {
  security_group_id = aws_security_group.redis.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "All outbound (packages, S3 backups, Secrets Manager)"
}

# Clients (Kubernetes pods, VPN users) and replication between the nodes.
resource "aws_vpc_security_group_ingress_rule" "redis_from_vpc" {
  for_each = {
    redis    = 6379
    sentinel = 26379
  }

  security_group_id = aws_security_group.redis.id
  ip_protocol       = "tcp"
  from_port         = each.value
  to_port           = each.value
  cidr_ipv4         = var.vpc_cidr
  description       = "${title(each.key)} from the VPC"
}

resource "aws_vpc_security_group_ingress_rule" "redis_ssh_from_vpn" {
  security_group_id            = aws_security_group.redis.id
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = var.ssh_source_security_group_id
  description                  = "SSH from VPN clients"
}

resource "aws_vpc_security_group_ingress_rule" "redis_icmp_from_vpc" {
  security_group_id = aws_security_group.redis.id
  ip_protocol       = "icmp"
  from_port         = -1
  to_port           = -1
  cidr_ipv4         = var.vpc_cidr
  description       = "ICMP from the VPC"
}

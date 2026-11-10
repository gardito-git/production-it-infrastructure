locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# Every rule is its own resource, as in the other modules.
resource "aws_security_group" "rabbitmq" {
  name        = "${local.name_prefix}-rabbitmq"
  description = "RabbitMQ cluster nodes"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${local.name_prefix}-rabbitmq"
  }
}

resource "aws_vpc_security_group_egress_rule" "rabbitmq_all" {
  security_group_id = aws_security_group.rabbitmq.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "All outbound (packages, S3 backups, Secrets Manager)"
}

# Apps anywhere in the VPC (Kubernetes pods leave from their node's IP).
# Prometheus scrapes the metrics endpoint from inside the VPC too.
resource "aws_vpc_security_group_ingress_rule" "rabbitmq_from_vpc" {
  for_each = {
    amqp       = 5672
    prometheus = 15692
  }

  security_group_id = aws_security_group.rabbitmq.id
  ip_protocol       = "tcp"
  from_port         = each.value
  to_port           = each.value
  cidr_ipv4         = var.vpc_cidr
  description       = "${upper(each.key)} from the VPC"
}

# Node-to-node only: epmd (4369) tells nodes each other's distribution port,
# and Erlang distribution (25672) carries clustering and queue replication.
# Anyone who can reach 25672 with the Erlang cookie controls the cluster, so
# these ports stay limited to the nodes themselves.
resource "aws_vpc_security_group_ingress_rule" "rabbitmq_cluster_self" {
  for_each = {
    epmd         = 4369
    distribution = 25672
  }

  security_group_id            = aws_security_group.rabbitmq.id
  ip_protocol                  = "tcp"
  from_port                    = each.value
  to_port                      = each.value
  referenced_security_group_id = aws_security_group.rabbitmq.id
  description                  = "Erlang ${each.key} between RabbitMQ nodes"
}

# People on the VPN: management UI and SSH. Never the whole VPC: the UI's
# admin login can change or delete everything.
resource "aws_vpc_security_group_ingress_rule" "rabbitmq_from_vpn" {
  for_each = {
    management = 15672
    ssh        = 22
  }

  security_group_id            = aws_security_group.rabbitmq.id
  ip_protocol                  = "tcp"
  from_port                    = each.value
  to_port                      = each.value
  referenced_security_group_id = var.vpn_security_group_id
  description                  = "${title(each.key)} from VPN clients"
}

resource "aws_vpc_security_group_ingress_rule" "rabbitmq_icmp_from_vpc" {
  security_group_id = aws_security_group.rabbitmq.id
  ip_protocol       = "icmp"
  from_port         = -1
  to_port           = -1
  cidr_ipv4         = var.vpc_cidr
  description       = "ICMP from the VPC"
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# Two groups: Elasticsearch nodes (masters + data) and Kibana.
# Every rule is its own resource, as in the other modules.

# Elasticsearch

resource "aws_security_group" "elasticsearch" {
  name        = "${local.name_prefix}-elasticsearch"
  description = "Elasticsearch master and data nodes"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${local.name_prefix}-elasticsearch"
  }
}

resource "aws_vpc_security_group_egress_rule" "es_all" {
  security_group_id = aws_security_group.elasticsearch.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "All outbound (packages, S3 snapshots, Secrets Manager)"
}

# REST API for applications (Kubernetes pods), Kibana and VPN users.
resource "aws_vpc_security_group_ingress_rule" "es_rest_from_vpc" {
  security_group_id = aws_security_group.elasticsearch.id
  ip_protocol       = "tcp"
  from_port         = 9200
  to_port           = 9200
  cidr_ipv4         = var.vpc_cidr
  description       = "Elasticsearch REST API (HTTP, login required) from the VPC"
}

# Node-to-node transport: cluster state, shard replication, searches across nodes.
resource "aws_vpc_security_group_ingress_rule" "es_transport_self" {
  security_group_id            = aws_security_group.elasticsearch.id
  ip_protocol                  = "tcp"
  from_port                    = 9300
  to_port                      = 9300
  referenced_security_group_id = aws_security_group.elasticsearch.id
  description                  = "Elasticsearch transport, between the nodes only (this rule decides who may join)"
}

resource "aws_vpc_security_group_ingress_rule" "es_ssh_from_vpn" {
  security_group_id            = aws_security_group.elasticsearch.id
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = var.vpn_security_group_id
  description                  = "SSH from VPN clients"
}

resource "aws_vpc_security_group_ingress_rule" "es_icmp_from_vpc" {
  security_group_id = aws_security_group.elasticsearch.id
  ip_protocol       = "icmp"
  from_port         = -1
  to_port           = -1
  cidr_ipv4         = var.vpc_cidr
  description       = "ICMP from the VPC"
}

# Kibana: only developers on the VPN.

resource "aws_security_group" "kibana" {
  name        = "${local.name_prefix}-kibana"
  description = "Kibana, for developers on the VPN"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${local.name_prefix}-kibana"
  }
}

resource "aws_vpc_security_group_egress_rule" "kibana_all" {
  security_group_id = aws_security_group.kibana.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "All outbound (Elasticsearch, packages, Secrets Manager)"
}

resource "aws_vpc_security_group_ingress_rule" "kibana_from_vpn" {
  for_each = {
    kibana = 5601
    ssh    = 22
  }

  security_group_id            = aws_security_group.kibana.id
  ip_protocol                  = "tcp"
  from_port                    = each.value
  to_port                      = each.value
  referenced_security_group_id = var.vpn_security_group_id
  description                  = "${title(each.key)} from VPN clients"
}

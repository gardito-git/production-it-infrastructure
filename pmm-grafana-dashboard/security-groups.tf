# Everything comes from inside the VPC: agents push metrics (443) and logs
# (3100), Kubernetes remote-writes metrics (9090), VPN users open the UI (443).
# Every rule is its own resource, as in the other modules.
resource "aws_security_group" "monitoring" {
  name        = "${local.name_prefix}-monitoring"
  description = "PMM, Loki and Prometheus"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${local.name_prefix}-monitoring"
  }
}

resource "aws_vpc_security_group_ingress_rule" "monitoring_from_vpc" {
  for_each = {
    pmm        = 443  # Grafana/PMM UI and pmm-agent (metrics are pushed over HTTPS)
    loki       = 3100 # Alloy pushes logs
    prometheus = 9090 # Kubernetes remote write
  }

  security_group_id = aws_security_group.monitoring.id
  ip_protocol       = "tcp"
  from_port         = each.value
  to_port           = each.value
  cidr_ipv4         = var.vpc_cidr
  description       = "${title(each.key)} from the VPC"
}

resource "aws_vpc_security_group_ingress_rule" "monitoring_ssh_from_vpn" {
  security_group_id            = aws_security_group.monitoring.id
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = var.vpn_security_group_id
  description                  = "SSH from VPN clients"
}

resource "aws_vpc_security_group_egress_rule" "monitoring_all" {
  security_group_id = aws_security_group.monitoring.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "All outbound (images, S3, GitHub login, Slack alerts)"
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# Two groups: the internet may reach the ALB, and only the ALB may reach the servers.
# Every rule is its own resource, as in the other modules.

# Load balancer

resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-web-alb"
  description = "Public web load balancer"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${local.name_prefix}-web-alb"
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_public" {
  for_each = {
    http  = 80
    https = 443
  }

  security_group_id = aws_security_group.alb.id
  ip_protocol       = "tcp"
  from_port         = each.value
  to_port           = each.value
  cidr_ipv4         = "0.0.0.0/0"
  description       = "${upper(each.key)} from the internet"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_web" {
  security_group_id            = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  referenced_security_group_id = aws_security_group.web_server.id
  description                  = "Requests and health checks to the web servers"
}

# Web servers

resource "aws_security_group" "web_server" {
  name        = "${local.name_prefix}-web-server"
  description = "Nginx web servers behind the ALB"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${local.name_prefix}-web-server"
  }
}

resource "aws_vpc_security_group_ingress_rule" "web_from_alb" {
  security_group_id            = aws_security_group.web_server.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  referenced_security_group_id = aws_security_group.alb.id
  description                  = "HTTP from the load balancer only"
}

# SSH is never open to the internet; only people connected to the VPN.
resource "aws_vpc_security_group_ingress_rule" "web_ssh_from_vpn" {
  security_group_id            = aws_security_group.web_server.id
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = var.ssh_source_security_group_id
  description                  = "SSH from VPN clients"
}

resource "aws_vpc_security_group_egress_rule" "web_all" {
  security_group_id = aws_security_group.web_server.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "All outbound via NAT (packages, upstream apps)"
}

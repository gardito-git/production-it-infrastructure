locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# Two groups: CloudFront (through its VPC origin) may reach the ALB, and only the
# ALB may reach the servers.
# Every rule is its own resource, as in the other modules.

# Load balancer

resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-web-alb"
  description = "Internal web load balancer, reached by CloudFront VPC origin"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${local.name_prefix}-web-alb"
  }
}

# CloudFront's VPC origin connects from network interfaces inside the VPC, so
# the VPC CIDR is the source. The ALB has no public IP, so nothing outside the
# VPC can use this rule.
resource "aws_vpc_security_group_ingress_rule" "alb_from_vpc" {
  security_group_id = aws_security_group.alb.id
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = var.vpc_cidr
  description       = "HTTP from CloudFront VPC origin (inside the VPC)"
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

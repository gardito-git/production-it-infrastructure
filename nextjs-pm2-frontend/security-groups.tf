# CloudFront (via its VPC origin) may reach the ALB; only the ALB may reach the
# servers. Every rule is its own resource, as in the other modules.

# Load balancer

resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-frontend-alb"
  description = "Internal Next.js load balancer, reached by CloudFront VPC origin"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${local.name_prefix}-frontend-alb"
  }
}

# CloudFront's VPC origin connects from ENIs inside the VPC, so the VPC CIDR is
# the source. The ALB has no public IP, so nothing outside the VPC matches.
resource "aws_vpc_security_group_ingress_rule" "alb_from_vpc" {
  security_group_id = aws_security_group.alb.id
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = var.vpc_cidr
  description       = "HTTP from CloudFront VPC origin (inside the VPC)"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_frontend" {
  security_group_id            = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
  referenced_security_group_id = aws_security_group.frontend.id
  description                  = "Requests and health checks to Next.js"
}

# Servers

resource "aws_security_group" "frontend" {
  name        = "${local.name_prefix}-frontend"
  description = "Next.js servers (PM2) behind the internal ALB"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${local.name_prefix}-frontend"
  }
}

resource "aws_vpc_security_group_ingress_rule" "frontend_from_alb" {
  security_group_id            = aws_security_group.frontend.id
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
  referenced_security_group_id = aws_security_group.alb.id
  description                  = "Next.js from the load balancer only"
}

resource "aws_vpc_security_group_ingress_rule" "frontend_ssh_from_vpn" {
  security_group_id            = aws_security_group.frontend.id
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = var.ssh_source_security_group_id
  description                  = "SSH from VPN clients"
}

resource "aws_vpc_security_group_egress_rule" "frontend_all" {
  security_group_id = aws_security_group.frontend.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "All outbound via NAT (Node.js download, S3, your APIs)"
}

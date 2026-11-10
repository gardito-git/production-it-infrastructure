# Only the Nginx servers (web-server module) may reach Next.js; people on the
# VPN may SSH in. Every rule is its own resource, as in the other modules.

resource "aws_security_group" "frontend" {
  name        = "${local.name_prefix}-frontend"
  description = "Next.js servers (PM2), reached through the Nginx reverse proxy"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${local.name_prefix}-frontend"
  }
}

resource "aws_vpc_security_group_ingress_rule" "frontend_from_nginx" {
  security_group_id            = aws_security_group.frontend.id
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
  referenced_security_group_id = var.proxy_security_group_id
  description                  = "Next.js from the Nginx reverse proxy only"
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

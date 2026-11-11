# Ports 80 and 443 are open to the internet because developers push and pull
# from anywhere, and Let's Encrypt validates from changing addresses. WHAT each
# client may reach is decided by the host's Nginx (scripts/harbor-nginx.sh):
# from the internet only the Docker API, from the VPC everything.
# Every rule is its own resource, as in the other modules.
resource "aws_security_group" "harbor" {
  name        = "${local.name_prefix}-harbor"
  description = "Harbor container registry"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${local.name_prefix}-harbor"
  }
}

resource "aws_vpc_security_group_ingress_rule" "harbor_public" {
  for_each = {
    http  = 80
    https = 443
  }

  security_group_id = aws_security_group.harbor.id
  ip_protocol       = "tcp"
  from_port         = each.value
  to_port           = each.value
  cidr_ipv4         = "0.0.0.0/0"
  description       = "${upper(each.key)} from anywhere (Docker clients, Let's Encrypt)"
}

resource "aws_vpc_security_group_ingress_rule" "harbor_ssh_from_vpn" {
  security_group_id            = aws_security_group.harbor.id
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = var.vpn_security_group_id
  description                  = "SSH from VPN clients"
}

resource "aws_vpc_security_group_egress_rule" "harbor_all" {
  security_group_id = aws_security_group.harbor.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "All outbound (packages, Docker images, S3, Let's Encrypt, Trivy database)"
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# No inbound traffic is needed: runners connect OUT to GitHub (HTTPS) and ask
# for jobs. Only people on the VPN may SSH in. Every rule is its own resource,
# as in the other modules.
resource "aws_security_group" "runner" {
  name        = "${local.name_prefix}-github-runner"
  description = "GitHub Actions self-hosted runners"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${local.name_prefix}-github-runner"
  }
}

resource "aws_vpc_security_group_ingress_rule" "runner_ssh_from_vpn" {
  security_group_id            = aws_security_group.runner.id
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = var.ssh_source_security_group_id
  description                  = "SSH from VPN clients"
}

# GitHub, package registries (npm, PyPI, Maven, Docker Hub...), AWS APIs, and
# the servers jobs deploy to.
resource "aws_vpc_security_group_egress_rule" "runner_all" {
  security_group_id = aws_security_group.runner.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "All outbound via NAT (GitHub, registries, AWS, deploy targets)"
}

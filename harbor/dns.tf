# Inside the VPC and on the VPN, the Harbor name resolves to the server's PRIVATE
# IP. That's what makes the UI VPN-only: those requests arrive from VPC addresses,
# which the host's Nginx allows everywhere. On the internet, your public DNS
# record points the same name at the Elastic IP, where only the Docker API works.
#
# The zone is the Harbor hostname itself, not the whole domain, so every other
# name under your domain keeps resolving normally. The VPN uses the VPC's
# resolver (vpc/vpn.tf), so VPN clients see this zone automatically.
resource "aws_route53_zone" "harbor_private" {
  name    = var.domain_name
  comment = "Private view of ${var.domain_name} for the VPC and VPN"

  vpc {
    vpc_id = var.vpc_id
  }

  tags = {
    Name = "${local.name_prefix}-harbor-private"
  }
}

resource "aws_route53_record" "harbor_private" {
  zone_id = aws_route53_zone.harbor_private.zone_id
  name    = var.domain_name
  type    = "A"
  ttl     = 300
  records = [local.private_ip]
}

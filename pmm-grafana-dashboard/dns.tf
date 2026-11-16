# The UI's private name, resolved inside the VPC and on the VPN (the VPN uses
# the VPC's resolver). The zone is the hostname itself, so nothing else is affected.
resource "aws_route53_zone" "monitoring" {
  name    = var.domain_name
  comment = "Private name of the monitoring server"

  vpc {
    vpc_id = var.vpc_id
  }

  tags = {
    Name = "${local.name_prefix}-monitoring"
  }
}

resource "aws_route53_record" "monitoring" {
  zone_id = aws_route53_zone.monitoring.zone_id
  name    = var.domain_name
  type    = "A"
  ttl     = 300
  records = [local.private_ip]
}

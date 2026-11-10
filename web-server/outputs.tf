# Values this module hands back to its caller, read as module.web_server.<name>.

output "alb_dns_name" {
  description = "Internal DNS name of the load balancer: the CloudFront origin domain (resolves to private IPs)"
  value       = aws_lb.web.dns_name
}

output "cloudfront_vpc_origin_id" {
  description = "Use as vpc_origin_id in a CloudFront distribution's origin to reach this ALB"
  value       = aws_cloudfront_vpc_origin.web.id
}

output "security_group_id" {
  description = "The Nginx servers' security group, for rules that let them reach upstreams"
  value       = aws_security_group.web_server.id
}

output "private_ips" {
  description = "Private IPs of web-1, web-2, web-3, for SSH over the VPN"
  value       = aws_instance.web_server[*].private_ip
}

output "instance_ids" {
  value = aws_instance.web_server[*].id
}

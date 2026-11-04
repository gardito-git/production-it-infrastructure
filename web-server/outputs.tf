# Values this module hands back to its caller, read as module.web_server.<name>.

output "alb_dns_name" {
  description = "Public DNS name of the load balancer: point your domain at it (CNAME, or a Route 53 alias)"
  value       = aws_lb.web.dns_name
}

output "alb_zone_id" {
  description = "Hosted zone ID of the load balancer, for a Route 53 alias record"
  value       = aws_lb.web.zone_id
}

output "private_ips" {
  description = "Private IPs of web-1, web-2, web-3, for SSH over the VPN"
  value       = aws_instance.web_server[*].private_ip
}

output "instance_ids" {
  value = aws_instance.web_server[*].id
}

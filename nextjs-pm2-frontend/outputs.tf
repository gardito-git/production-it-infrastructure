# Values this module hands back to its caller, read as module.nextjs_frontend.<name>.

output "url" {
  description = "The site: your first domain, or the *.cloudfront.net address"
  value       = "https://${length(var.domain_names) > 0 ? var.domain_names[0] : aws_cloudfront_distribution.frontend.domain_name}"
}

output "cloudfront_domain" {
  description = "Point your domain at this (CNAME, or a Route 53 alias with cloudfront_zone_id)"
  value       = aws_cloudfront_distribution.frontend.domain_name
}

output "cloudfront_zone_id" {
  value = aws_cloudfront_distribution.frontend.hosted_zone_id
}

output "distribution_id" {
  description = "For cache invalidations"
  value       = aws_cloudfront_distribution.frontend.id
}

output "bucket_name" {
  description = "Releases and static files: pass it to scripts/release.sh"
  value       = aws_s3_bucket.frontend.id
}

output "private_ips" {
  description = "Private IPs of frontend-1, -2, -3, for SSH over the VPN"
  value       = aws_instance.frontend[*].private_ip
}

output "instance_ids" {
  value = aws_instance.frontend[*].id
}

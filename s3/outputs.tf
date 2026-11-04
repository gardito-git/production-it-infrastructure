# Values this module hands back to its caller, read as module.s3.<name>.

output "private_bucket_name" {
  value = aws_s3_bucket.private.id
}

output "private_bucket_arn" {
  description = "For IAM policies that grant other services access to a prefix"
  value       = aws_s3_bucket.private.arn
}

output "frontend_bucket_name" {
  value = aws_s3_bucket.frontend.id
}

output "frontend_cdn_domain" {
  description = "Public HTTPS domain serving the frontend bucket"
  value       = aws_cloudfront_distribution.frontend.domain_name
}

output "frontend_cdn_distribution_id" {
  description = "Needed for cache invalidations after a deploy"
  value       = aws_cloudfront_distribution.frontend.id
}

output "frontend_developers_group" {
  description = "IAM group to add frontend team members to"
  value       = aws_iam_group.frontend_developers.name
}

# Values this module hands back to its caller, read as module.s3.<name>.

output "private_bucket_name" {
  value = aws_s3_bucket.private.id
}

output "private_bucket_arn" {
  description = "For IAM policies that grant other services access to a prefix"
  value       = aws_s3_bucket.private.arn
}

output "public_bucket_name" {
  value = aws_s3_bucket.public.id
}

output "public_cdn_domain" {
  description = "Public HTTPS domain serving the public bucket"
  value       = aws_cloudfront_distribution.public.domain_name
}

output "public_cdn_distribution_id" {
  description = "Needed for cache invalidations after a deploy"
  value       = aws_cloudfront_distribution.public.id
}

output "web_developers_group" {
  description = "IAM group to add web team members to"
  value       = aws_iam_group.web_developers.name
}

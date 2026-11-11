# Values this module hands back to its caller, read as module.harbor.<name>.

output "public_ip" {
  description = "Elastic IP: create the public DNS A record for domain_name pointing here"
  value       = aws_eip.harbor.public_ip
}

output "private_ip" {
  description = "Fixed private IP, for SSH over the VPN"
  value       = local.private_ip
}

output "url" {
  description = "Harbor UI, over the VPN"
  value       = "https://${var.domain_name}"
}

output "bucket_name" {
  description = "S3 bucket holding the image layers"
  value       = aws_s3_bucket.harbor.id
}

output "secret_arn" {
  description = "Secrets Manager secret with the admin and database passwords"
  value       = aws_secretsmanager_secret.harbor.arn
}

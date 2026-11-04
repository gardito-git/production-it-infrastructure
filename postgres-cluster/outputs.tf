# Values this module hands back to its caller, read as module.postgres_cluster.<name>.

output "endpoint" {
  description = "Internal DNS name of the PostgreSQL load balancer"
  value       = aws_lb.postgres.dns_name
}

output "read_write_port" {
  description = "Port on endpoint that always reaches the primary"
  value       = 5432
}

output "read_only_port" {
  description = "Port on endpoint that reaches the replicas"
  value       = 5433
}

output "node_private_ips" {
  description = "Fixed private IPs of pg-1, pg-2, pg-3 (for SSH over the VPN)"
  value       = aws_instance.postgres[*].private_ip
}

output "secret_arn" {
  description = "Secrets Manager secret with the superuser password and connection details"
  value       = aws_secretsmanager_secret.postgres.arn
}

output "backup_location" {
  description = "Where the pgBackRest backups and WAL archive are stored"
  value       = "s3://${var.backup_bucket_name}/${var.backup_prefix}/"
}

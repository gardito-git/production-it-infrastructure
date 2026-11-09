# Values this module hands back to its caller, read as module.redis_sentinel.<name>.

output "sentinel_endpoints" {
  description = "Give these to Sentinel-aware clients; they ask the sentinels where the master is"
  value       = [for ip in local.node_ips : "${ip}:26379"]
}

output "sentinel_master_name" {
  value = var.sentinel_master_name
}

output "node_private_ips" {
  description = "Fixed private IPs of redis-1, redis-2, redis-3 (for SSH over the VPN)"
  value       = aws_instance.redis[*].private_ip
}

output "secret_arn" {
  description = "Secrets Manager secret with the password and connection details"
  value       = aws_secretsmanager_secret.redis.arn
}

output "backup_location" {
  description = "Where the daily RDB backups are stored"
  value       = "s3://${var.backup_bucket_name}/${var.backup_prefix}/"
}

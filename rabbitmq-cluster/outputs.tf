# Values this module hands back to its caller, read as module.rabbitmq_cluster.<name>.

output "amqp_endpoints" {
  description = "Give apps all three; clients connect to one and move to another if it fails"
  value       = [for ip in local.node_ips : "${ip}:5672"]
}

output "management_url" {
  description = "Management UI, over the VPN (log in as admin; password in secret_arn)"
  value       = "http://${local.node_ips[0]}:15672"
}

output "node_private_ips" {
  description = "Fixed private IPs of rabbitmq-1, rabbitmq-2, rabbitmq-3 (for SSH over the VPN)"
  value       = aws_instance.rabbitmq[*].private_ip
}

output "secret_arn" {
  description = "Secrets Manager secret with the admin password, Erlang cookie and connection details"
  value       = aws_secretsmanager_secret.rabbitmq.arn
}

output "backup_location" {
  description = "Where the daily definitions backups are stored"
  value       = "s3://${var.backup_bucket_name}/${var.backup_prefix}/"
}

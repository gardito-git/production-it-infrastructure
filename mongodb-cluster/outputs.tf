# Values this module hands back to its caller, read as module.mongodb_cluster.<name>.

output "connection_string" {
  description = "For apps: replace <user>/<password> with an app user (see README). Lists all 3 members; the driver finds the primary."
  value       = "mongodb://<user>:<password>@${join(",", [for ip in local.node_ips : "${ip}:27017"])}/?replicaSet=${var.replica_set_name}&authSource=admin"
}

output "hosts" {
  value = [for ip in local.node_ips : "${ip}:27017"]
}

output "replica_set_name" {
  value = var.replica_set_name
}

output "node_private_ips" {
  description = "Fixed private IPs of mongodb-1, mongodb-2, mongodb-3 (for SSH over the VPN)"
  value       = aws_instance.mongodb[*].private_ip
}

output "secret_arn" {
  description = "Secrets Manager secret with the admin and backup passwords and the keyfile"
  value       = aws_secretsmanager_secret.mongodb.arn
}

output "backup_location" {
  description = "Where the daily mongodump archives are stored"
  value       = "s3://${var.backup_bucket_name}/${var.backup_prefix}/"
}

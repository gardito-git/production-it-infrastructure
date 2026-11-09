# Values this module hands back to its caller, read as module.elasticsearch_cluster.<name>.

output "kibana_url" {
  description = "Kibana, reachable over the VPN (log in as elastic)"
  value       = "http://${local.kibana_ip}:5601"
}

output "elasticsearch_hosts" {
  description = "REST endpoints for applications (plain HTTP with username/password or API key, the data nodes)"
  value       = [for ip in local.data_ips : "http://${ip}:9200"]
}

output "master_private_ips" {
  value = local.master_ips
}

output "data_private_ips" {
  value = local.data_ips
}

output "secret_arn" {
  description = "Secrets Manager secret with the elastic password"
  value       = aws_secretsmanager_secret.elasticsearch.arn
}

output "snapshot_location" {
  description = "S3 snapshot repository \"s3-backups\""
  value       = "s3://${var.backup_bucket_name}/${var.backup_prefix}/"
}

# Re-export module outputs so `terraform output` shows them after apply.

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnet_ids" {
  value = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.vpc.private_subnet_ids
}

output "vpn_endpoint_id" {
  value = module.vpc.vpn_endpoint_id
}

# Save a profile with:
#   terraform output -json vpn_client_configs | jq -r '.admin' > admin.ovpn
output "vpn_client_configs" {
  value     = module.vpc.vpn_client_configs
  sensitive = true
}

output "kubernetes_api_endpoint" {
  value = module.kubernetes_cluster.api_endpoint
}

output "kubernetes_bootstrap_bucket" {
  value = module.kubernetes_cluster.bootstrap_bucket
}

output "control_plane_instance_ids" {
  value = module.kubernetes_cluster.control_plane_instance_ids
}

output "control_plane_private_ips" {
  value = module.kubernetes_cluster.control_plane_private_ips
}

output "worker_private_ips" {
  value = module.kubernetes_cluster.worker_private_ips
}

output "etcd_private_ips" {
  value = module.kubernetes_cluster.etcd_private_ips
}

output "postgres_endpoint" {
  description = "Port 5432 = primary (read-write), 5433 = replicas (read-only)"
  value       = module.postgres_cluster.endpoint
}

output "postgres_node_private_ips" {
  value = module.postgres_cluster.node_private_ips
}

output "postgres_secret_arn" {
  value = module.postgres_cluster.secret_arn
}

output "postgres_backup_location" {
  value = module.postgres_cluster.backup_location
}

output "private_bucket_name" {
  value = module.s3.private_bucket_name
}

output "public_bucket_name" {
  value = module.s3.public_bucket_name
}

output "public_cdn_domain" {
  value = module.s3.public_cdn_domain
}

output "public_cdn_distribution_id" {
  value = module.s3.public_cdn_distribution_id
}

output "web_developers_group" {
  value = module.s3.web_developers_group
}

output "kubernetes_etcd_backup_location" {
  value = "s3://${module.s3.private_bucket_name}/backups/kubernetes/etcd/"
}

output "web_alb_dns_name" {
  description = "Public address of the web load balancer: point your domain at it"
  value       = module.web_server.alb_dns_name
}

output "web_server_private_ips" {
  value = module.web_server.private_ips
}

output "redis_sentinel_endpoints" {
  description = "Sentinel addresses for Sentinel-aware Redis clients (master name: redis_sentinel_master_name)"
  value       = module.redis_sentinel.sentinel_endpoints
}

output "redis_sentinel_master_name" {
  value = module.redis_sentinel.sentinel_master_name
}

output "redis_node_private_ips" {
  value = module.redis_sentinel.node_private_ips
}

output "redis_secret_arn" {
  value = module.redis_sentinel.secret_arn
}

output "redis_backup_location" {
  value = module.redis_sentinel.backup_location
}

output "kibana_url" {
  description = "Kibana, over the VPN (log in as elastic; password in elasticsearch_secret_arn)"
  value       = module.elasticsearch_cluster.kibana_url
}

output "elasticsearch_hosts" {
  value = module.elasticsearch_cluster.elasticsearch_hosts
}

output "elasticsearch_secret_arn" {
  value = module.elasticsearch_cluster.secret_arn
}

output "elasticsearch_snapshot_location" {
  value = module.elasticsearch_cluster.snapshot_location
}

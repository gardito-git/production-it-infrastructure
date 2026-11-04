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

output "postgres_backup_bucket" {
  value = module.postgres_cluster.backup_bucket
}

output "private_bucket_name" {
  value = module.s3.private_bucket_name
}

output "frontend_bucket_name" {
  value = module.s3.frontend_bucket_name
}

output "frontend_cdn_domain" {
  value = module.s3.frontend_cdn_domain
}

output "frontend_cdn_distribution_id" {
  value = module.s3.frontend_cdn_distribution_id
}

output "frontend_developers_group" {
  value = module.s3.frontend_developers_group
}

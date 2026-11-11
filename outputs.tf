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
  description = "Internal web load balancer (CloudFront's origin). Point your domain at frontend_cloudfront_domain instead."
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

output "frontend_url" {
  value = module.nextjs_frontend.url
}

output "frontend_cloudfront_domain" {
  description = "Point your domain at this"
  value       = module.nextjs_frontend.cloudfront_domain
}

output "frontend_distribution_id" {
  value = module.nextjs_frontend.distribution_id
}

output "frontend_bucket_name" {
  description = "Pass to nextjs-pm2-frontend/scripts/release.sh"
  value       = module.nextjs_frontend.bucket_name
}

output "frontend_private_ips" {
  description = "SSH over the VPN, then: sudo deploy-frontend <version>"
  value       = module.nextjs_frontend.private_ips
}

output "rabbitmq_amqp_endpoints" {
  description = "AMQP addresses of the 3 RabbitMQ nodes: give apps all of them"
  value       = module.rabbitmq_cluster.amqp_endpoints
}

output "rabbitmq_management_url" {
  description = "RabbitMQ management UI, over the VPN (admin password in rabbitmq_secret_arn)"
  value       = module.rabbitmq_cluster.management_url
}

output "rabbitmq_node_private_ips" {
  value = module.rabbitmq_cluster.node_private_ips
}

output "rabbitmq_secret_arn" {
  value = module.rabbitmq_cluster.secret_arn
}

output "rabbitmq_backup_location" {
  value = module.rabbitmq_cluster.backup_location
}

output "github_runner_secret_arn" {
  description = "Put the GitHub token here once (see github-runner/README.md)"
  value       = module.github_runner.secret_arn
}

output "github_runner_names" {
  value = module.github_runner.runner_names
}

output "github_runner_private_ips" {
  value = module.github_runner.private_ips
}

output "harbor_public_ip" {
  description = "Create the public DNS A record for Harbor pointing here"
  value       = module.harbor.public_ip
}

output "harbor_private_ip" {
  value = module.harbor.private_ip
}

output "harbor_url" {
  description = "Harbor UI, over the VPN"
  value       = module.harbor.url
}

output "harbor_bucket_name" {
  value = module.harbor.bucket_name
}

output "harbor_secret_arn" {
  value = module.harbor.secret_arn
}

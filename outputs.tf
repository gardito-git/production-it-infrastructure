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

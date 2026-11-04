# Values this module hands back to its caller, read as module.kubernetes_cluster.<name>.

output "api_endpoint" {
  description = "Internal NLB DNS name for the Kubernetes API (port 6443)"
  value       = aws_lb.api.dns_name
}

output "bootstrap_bucket" {
  description = "S3 bucket holding the short-lived bootstrap secrets"
  value       = aws_s3_bucket.bootstrap.id
}

output "control_plane_instance_ids" {
  value = aws_instance.control_plane[*].id
}

output "control_plane_private_ips" {
  value = aws_instance.control_plane[*].private_ip
}

output "worker_private_ips" {
  value = aws_instance.worker[*].private_ip
}

output "etcd_private_ips" {
  value = aws_instance.etcd[*].private_ip
}

output "node_instance_profile_names" {
  value = { for k, p in aws_iam_instance_profile.node : k => p.name }
}

output "node_role_names" {
  value = { for k, r in aws_iam_role.node : k => r.name }
}

# Values this module hands back to its caller, read as module.kubernetes_cluster.<name>.

output "control_plane_private_ips" {
  value = aws_instance.control_plane[*].private_ip
}

output "worker_private_ips" {
  value = aws_instance.worker[*].private_ip
}

output "etcd_private_ips" {
  value = aws_instance.etcd[*].private_ip
}

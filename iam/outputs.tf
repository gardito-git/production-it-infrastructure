# Values this module hands back to its caller, read as module.iam.<name>.
# Both are maps keyed by node type: "control-plane", "worker", "etcd".

output "node_instance_profile_names" {
  value = { for k, p in aws_iam_instance_profile.node : k => p.name }
}

output "node_role_names" {
  value = { for k, r in aws_iam_role.node : k => r.name }
}

# Values this module hands back to its caller, read as module.iam.<name>.

output "node_instance_profile_name" {
  value = aws_iam_instance_profile.node.name
}

output "node_role_arn" {
  value = aws_iam_role.node.arn
}

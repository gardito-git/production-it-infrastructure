# Values this module hands back to its caller, read as module.github_runner.<name>.

output "secret_arn" {
  description = "Put the GitHub token here after the first apply (see README)"
  value       = aws_secretsmanager_secret.github.arn
}

output "runner_names" {
  description = "Names the runners register with in GitHub"
  value       = [for i in range(var.runner_count) : "${local.name_prefix}-runner-${i + 1}"]
}

output "private_ips" {
  description = "For SSH over the VPN"
  value       = aws_instance.runner[*].private_ip
}

output "role_name" {
  description = "The runners' IAM role (jobs get its permissions)"
  value       = aws_iam_role.runner.name
}

output "security_group_id" {
  description = "The runners' security group, for rules that let jobs reach other servers"
  value       = aws_security_group.runner.id
}

# Values this module hands back to its caller, read as module.pmm_grafana_dashboard.<name>.

output "url" {
  description = "Grafana/PMM UI, over the VPN"
  value       = "https://${var.domain_name}"
}

output "private_ip" {
  value = local.private_ip
}

output "admin_secret_arn" {
  description = "Grafana/PMM admin password"
  value       = aws_secretsmanager_secret.admin.arn
}

output "github_secret_arn" {
  description = "Put the GitHub OAuth app's client_id and client_secret here (README)"
  value       = aws_secretsmanager_secret.github.arn
}

output "loki_bucket_name" {
  value = aws_s3_bucket.loki.id
}

# Passed to every other module as `monitoring`: the agent installer (with this
# server's addresses baked in) and the IAM policy to read the agent token.
output "agent" {
  description = "Monitoring agent settings for the other modules' `monitoring` input"
  value = {
    agent_script = local.agent_script
    policy_arn   = aws_iam_policy.agent.arn
  }
}

output "agent_script" {
  description = "The rendered agent installer, for the Ansible playbook (existing servers)"
  value       = local.agent_script
}

# Inputs this module accepts. The root module passes them in via the
# module "github_runner" block in main.tf.

variable "project_name" {
  type        = string
  description = "Project name used in resource names"
}

variable "environment" {
  type        = string
  description = "Environment name used in resource names"
}

variable "vpc_id" {
  type        = string
  description = "VPC to create the security group in (module.vpc.vpc_id)"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnets the runners are spread over, one per AZ (module.vpc.private_subnet_ids)"
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key installed on every runner for user \"ubuntu\""
}

variable "ssh_source_security_group_id" {
  type        = string
  description = "Security group allowed to SSH to the runners: the VPN endpoint's (module.vpc.vpn_security_group_id)"
}

variable "github_scope" {
  type        = string
  # default     = "my-org/my-repo" # TO-DO
  description = <<-EOT
    Where the runners register: an organization ("my-org"), so every repository in it can
    use them, or one repository ("my-org/my-repo"). A personal account without an
    organization can only use the repository form.
  EOT

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)?$", var.github_scope))
    error_message = "github_scope must be an organization (\"my-org\") or a repository (\"my-org/my-repo\")."
  }
}

variable "runner_count" {
  type        = number
  default     = 3
  description = "Number of runners, spread round-robin over the private subnets. Each runs one job at a time."
}

variable "runner_labels" {
  type        = list(string)
  default     = ["aws", "vpc"]
  description = "Extra labels, on top of GitHub's automatic self-hosted, linux, x64. Workflows pick runners with runs-on: [self-hosted, vpc]."
}

variable "runner_group" {
  type        = string
  default     = "Default"
  description = "Organization runner group the runners join (ignored for a repository scope). The Default group lets every private repository use them."
}

variable "runner_version" {
  type        = string
  default     = "2.338.2"
  description = "GitHub Actions runner version installed at first boot (checked against its SHA-256). Runners then update themselves."

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.runner_version))
    error_message = "runner_version must look like \"2.338.2\" (no leading v)."
  }
}

variable "policy_arns" {
  type        = map(string)
  default     = {}
  description = "Extra IAM policies for the runners' role, e.g. { frontend_deployer = module.nextjs_frontend.deployer_policy_arn }. Keys are just names."
}

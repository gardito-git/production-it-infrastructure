# Inputs this module accepts. The root module passes them in via the
# module "nextjs_frontend" block in main.tf.

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
  description = "VPC for the load balancer and servers (module.vpc.vpc_id)"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR. CloudFront's VPC origin reaches the internal load balancer from IPs inside it."
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnets for the internal load balancer and the servers, at least 2 AZs (module.vpc.private_subnet_ids)"
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key installed on every server for user \"ubuntu\""
}

variable "ssh_source_security_group_id" {
  type        = string
  description = "Security group allowed to SSH to the servers: the VPN endpoint's (module.vpc.vpn_security_group_id)"
}

variable "deployer_group_name" {
  type        = string
  default     = null
  description = "IAM group allowed to upload releases and static files (module.s3.web_developers_group). null = attach nothing."
}

variable "instance_count" {
  type        = number
  default     = 3
  description = "Number of Next.js servers, spread round-robin over the private subnets"
}

variable "instance_type" {
  type        = string
  default     = "c8i.large"
  description = "EC2 instance type of every server (2 vCPU, 4 GiB: PM2 runs one Next.js process per vCPU)"
}

variable "node_major" {
  type        = number
  default     = 24
  description = "Node.js major version (latest release of it is installed). Must match the version your release is built with."
}

variable "pm2_version" {
  type        = string
  default     = "6"
  description = "PM2 version for npm install -g pm2@<this>"
}

variable "app_port" {
  type        = number
  default     = 3000
  description = "Port Next.js listens on, on every server"
}

variable "health_check_path" {
  type        = string
  default     = "/"
  description = "Path the load balancer and deploy-frontend check. Any 2xx/3xx counts as healthy. A cheap /api/health route is better than a full page."
}

variable "domain_names" {
  type        = list(string)
  default     = []
  description = "Your own domains, e.g. [\"www.example.com\"]. Needs acm_certificate_arn. Empty = only the *.cloudfront.net address."
}

variable "acm_certificate_arn" {
  type        = string
  default     = null
  description = "ACM certificate covering domain_names. Must be in us-east-1, whatever region the rest runs in (a CloudFront rule)."
}

variable "cloudfront_price_class" {
  type        = string
  default     = "PriceClass_200"
  description = "CloudFront edge locations. PriceClass_200 includes Asia; PriceClass_100 is cheaper but only North America and Europe."
}

variable "github_repository" {
  type        = string
  default     = null
  description = "Your Next.js repository as \"owner/name\". Its v* tags may release through GitHub Actions (github-actions.tf). null = no CI role."

  validation {
    condition     = var.github_repository == null || can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must look like \"my-org/my-next-app\"."
  }
}

variable "github_oidc_provider_arn" {
  type        = string
  default     = null
  description = "ARN of an existing GitHub OIDC provider in this account (only one may exist). null = create it."
}

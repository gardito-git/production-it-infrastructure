# Inputs this module accepts. The root module passes them in via the
# module "web_server" block in main.tf.

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
  description = "VPC for the security groups and target group (module.vpc.vpc_id)"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR. Nginx trusts X-Forwarded-For only from here (the load balancer)."
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "Public subnets for the load balancer, at least 2 AZs (module.vpc.public_subnet_ids)"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnets the servers are spread across, one per AZ (module.vpc.private_subnet_ids)"
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key installed on every server for user \"ubuntu\""
}

variable "ssh_source_security_group_id" {
  type        = string
  description = "Security group allowed to SSH to the servers: the VPN endpoint's (module.vpc.vpn_security_group_id)"
}

variable "instance_count" {
  type        = number
  default     = 3
  description = "Number of web servers, spread round-robin over the private subnets"
}

variable "instance_type" {
  type        = string
  default     = "c8i.large"
  description = "EC2 instance type of every web server"
}

variable "certificate_arn" {
  type        = string
  default     = null
  description = <<-EOT
    ACM certificate for HTTPS (must be in the same region as the load balancer).
    Leave null to serve plain HTTP only. When set, port 443 serves HTTPS and
    port 80 redirects to it.
  EOT
}

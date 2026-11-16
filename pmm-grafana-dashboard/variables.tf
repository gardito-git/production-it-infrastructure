# Inputs this module accepts. The root module passes them in via the
# module "pmm_grafana_dashboard" block in main.tf.

variable "project_name" {
  type        = string
  description = "Project name used in resource names"
}

variable "environment" {
  type        = string
  description = "Environment name used in resource names and as the PMM environment label"
}

variable "vpc_id" {
  type        = string
  description = "VPC for the security group and the private DNS zone (module.vpc.vpc_id)"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR: agents, VPN users and Kubernetes send data from here"
}

variable "private_subnet_id" {
  type        = string
  description = "Private subnet for the monitoring server (module.vpc.private_subnet_ids[0])"
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key installed on the server for user \"ubuntu\""
}

variable "vpn_security_group_id" {
  type        = string
  description = "The VPN endpoint's security group (module.vpc.vpn_security_group_id): allowed to SSH in"
}

variable "domain_name" {
  type        = string
  default     = "monitoring.internal"
  description = "Private name of the Grafana/PMM UI, resolved inside the VPC and on the VPN. .internal is reserved for private use."
}

variable "github_organization" {
  type        = string
  default     = null
  description = "GitHub organization whose members may log in to Grafana (view-only). null = only Grafana's own users."
}

variable "pmm_version" {
  type        = string
  default     = "3.10.0"
  description = "PMM Server image tag (percona/pmm-server). Clients install the matching pmm3-client."
}

variable "loki_version" {
  type        = string
  default     = "3.7.10"
  description = "Loki image tag (grafana/loki)"
}

variable "prometheus_version" {
  type        = string
  default     = "3.16.0"
  description = "Prometheus image tag (prom/prometheus), used for Kubernetes metrics only"
}

variable "retention_days" {
  type        = number
  default     = 30
  description = "How long metrics (PMM and Prometheus) and logs (Loki) are kept"
}

variable "snapshot_retention_count" {
  type        = number
  default     = 7
  description = "Daily snapshots of the data volume to keep (dashboards, users, metrics history)"
}

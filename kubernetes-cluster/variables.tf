# Inputs this module accepts. The root module passes them in via the
# module "kubernetes_cluster" block in main.tf.

variable "project_name" {
  type        = string
  description = "Project name used in resource names and as the Kubernetes cluster name"
}

variable "environment" {
  type        = string
  description = "Environment name used in resource names"
}

variable "vpc_id" {
  type        = string
  description = "VPC to create the security groups in (module.vpc.vpc_id)"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR, allowed to reach the API server, NodePorts and ICMP"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnets the nodes are spread across (module.vpc.private_subnet_ids)"
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "CIDRs of private_subnet_ids, same order. Used to give etcd nodes fixed IPs."
}


variable "backup_bucket_name" {
  type        = string
  description = "Private bucket the etcd snapshots are uploaded to (module.s3.private_bucket_name)"
}

variable "backup_bucket_arn" {
  type        = string
  description = "ARN of backup_bucket_name, for the etcd nodes' IAM policy (module.s3.private_bucket_arn)"
}

variable "backup_prefix" {
  type        = string
  default     = "backups/kubernetes"
  description = "Key prefix (\"folder\") for Kubernetes backups, without leading or trailing slash. Snapshots go to <prefix>/etcd/."
}

variable "etcd_backup_schedule" {
  type        = string
  default     = "*-*-* 00/6:00:00"
  description = "When each etcd member uploads a snapshot, as a systemd OnCalendar expression (default: every 6 hours, UTC)"
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key installed on every node for user \"ubuntu\""
}

variable "ssh_source_security_group_id" {
  type        = string
  description = "Security group allowed to SSH to the nodes: the VPN endpoint's (module.vpc.vpn_security_group_id)"
}

variable "kubernetes_version" {
  type        = string
  default     = "1.37"
  description = "Kubernetes minor version; nodes install the latest patch from pkgs.k8s.io"
}

variable "cilium_version" {
  type        = string
  default     = "1.20.4"
  description = "Cilium (CNI) version installed by control-plane-1"
}

variable "cilium_cli_version" {
  type        = string
  default     = "0.20.2"
  description = "cilium-cli version used to install Cilium"
}

variable "pod_cidr" {
  type        = string
  default     = "10.244.0.0/16"
  description = "Pod IP range. Must not overlap the VPC or service_cidr."
}

variable "service_cidr" {
  type        = string
  default     = "10.96.0.0/12"
  description = "ClusterIP service range. Must not overlap the VPC or pod_cidr."
}

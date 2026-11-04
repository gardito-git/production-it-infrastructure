# Inputs this module accepts. The root module passes them in via the
# module "postgres_cluster" block in main.tf.

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
  description = "VPC to create the security group, NLB target groups in (module.vpc.vpc_id)"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR, allowed to connect to PostgreSQL (port 5432/5433) and in pg_hba.conf"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnets, one node per subnet/AZ (module.vpc.private_subnet_ids)"

  validation {
    condition     = length(var.private_subnet_ids) == 3
    error_message = "Exactly 3 private subnets are needed: one node per AZ, and etcd needs 3 members for a quorum."
  }
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "CIDRs of private_subnet_ids, same order. Used to give the nodes fixed IPs."
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key installed on every node for user \"ubuntu\""
}

variable "ssh_source_security_group_id" {
  type        = string
  description = "Security group allowed to SSH to the nodes: the VPN endpoint's (module.vpc.vpn_security_group_id)"
}

variable "instance_type" {
  type        = string
  default     = "r8i.xlarge"
  description = "Same for all 3 nodes, because any node can become the primary. r8i.xlarge = 4 vCPU, 32 GiB."
}

variable "data_volume_size" {
  type        = number
  default     = 200
  description = "Size in GiB of each node's gp3 data volume. Can be grown later, never shrunk."
}

variable "data_volume_iops" {
  type        = number
  default     = 3000
  description = "Provisioned IOPS of each data volume (gp3 includes 3000 free)"
}

variable "data_volume_throughput" {
  type        = number
  default     = 250
  description = "Throughput in MiB/s of each data volume (gp3 includes 125 free)"
}

variable "postgres_version" {
  type        = string
  default     = "18"
  description = "PostgreSQL major version. Changing it does NOT upgrade a running cluster."
}

variable "etcd_version" {
  type        = string
  default     = "3.6.16"
  description = "etcd release used by Patroni to elect the primary"
}

variable "backup_retention_full" {
  type        = number
  default     = 4
  description = "Number of weekly full backups pgBackRest keeps in S3 (4 = about a month of point-in-time restore)"
}

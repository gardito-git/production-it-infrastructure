# Inputs this module accepts. The root module passes them in via the
# module "mongodb_cluster" block in main.tf.

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

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR, allowed to connect to MongoDB (27017)"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnets, one node per subnet/AZ (module.vpc.private_subnet_ids)"

  validation {
    condition     = length(var.private_subnet_ids) == 3
    error_message = "Exactly 3 private subnets are needed: one member per AZ, so a majority (2 of 3) survives losing an AZ."
  }
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "CIDRs of private_subnet_ids, same order. Used to give the nodes fixed IPs (.100)."
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key installed on every node for user \"ubuntu\""
}

variable "ssh_source_security_group_id" {
  type        = string
  description = "Security group allowed to SSH to the nodes: the VPN endpoint's (module.vpc.vpn_security_group_id)"
}

variable "backup_bucket_name" {
  type        = string
  description = "Private bucket the daily mongodump archives go to (module.s3.private_bucket_name)"
}

variable "backup_bucket_arn" {
  type        = string
  description = "ARN of backup_bucket_name, for the nodes' IAM policy (module.s3.private_bucket_arn)"
}

variable "backup_prefix" {
  type        = string
  default     = "backups/mongodb"
  description = "Key prefix (\"folder\") for the backups, without leading or trailing slash"
}

variable "mongodb_version" {
  type        = string
  default     = "8.0"
  description = "MongoDB release series from repo.mongodb.org (newest patch of it is installed and held)"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.mongodb_version))
    error_message = "mongodb_version must be a release series like \"8.0\"."
  }
}

variable "replica_set_name" {
  type        = string
  default     = "rs0"
  description = "Replica set name; clients put it in the connection string (replicaSet=...)"
}

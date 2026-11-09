# Inputs this module accepts. The root module passes them in via the
# module "elasticsearch_cluster" block in main.tf.

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
  description = "VPC to create the security groups in (module.vpc.vpc_id)"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR, allowed to reach the Elasticsearch REST API (9200)"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnets, nodes spread one per AZ (module.vpc.private_subnet_ids)"

  validation {
    condition     = length(var.private_subnet_ids) == 3
    error_message = "Exactly 3 private subnets are needed: one master per AZ, and data nodes spread over all three."
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

variable "vpn_security_group_id" {
  type        = string
  description = "The VPN endpoint's security group (module.vpc.vpn_security_group_id): allowed to SSH in and to open Kibana"
}

variable "backup_bucket_name" {
  type        = string
  description = "Private bucket for the snapshot repository (module.s3.private_bucket_name)"
}

variable "backup_bucket_arn" {
  type        = string
  description = "ARN of backup_bucket_name, for the nodes' IAM policy (module.s3.private_bucket_arn)"
}

variable "backup_prefix" {
  type        = string
  default     = "backups/elasticsearch"
  description = "Key prefix (\"folder\") of the snapshot repository, without leading or trailing slash"
}

variable "elastic_version" {
  type        = string
  default     = "9.5.6"
  description = "Exact Elasticsearch and Kibana version. All nodes and Kibana must run the same one."
}

variable "master_instance_type" {
  type        = string
  default     = "c8i.xlarge"
  description = "Instance type of the 3 master nodes"
}

variable "data_instance_type" {
  type        = string
  default     = "r8i.xlarge"
  description = "Instance type of the data nodes (memory-optimized: heap + filesystem cache)"
}

variable "data_node_count" {
  type        = number
  default     = 6
  description = "Number of data nodes, spread round-robin over the 3 AZs. Use a multiple of 3."

  validation {
    condition     = var.data_node_count >= 3 && var.data_node_count % 3 == 0
    error_message = "data_node_count must be a multiple of 3 (at least 3), so every AZ holds the same share."
  }
}

variable "data_volume_size" {
  type        = number
  default     = 100
  description = "Size in GiB of each data node's gp3 volume"
}

variable "kibana_instance_type" {
  type        = string
  default     = "c8i.large"
  description = "Instance type of the Kibana node"
}

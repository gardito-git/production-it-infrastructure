# Inputs this module accepts. The root module passes them in via the
# module "redis_sentinel" block in main.tf.

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
  description = "VPC CIDR, allowed to connect to Redis (6379) and Sentinel (26379)"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnets, one node per subnet/AZ (module.vpc.private_subnet_ids)"

  validation {
    condition     = length(var.private_subnet_ids) == 3
    error_message = "Exactly 3 private subnets are needed: one node per AZ, and Sentinel needs 3 voters for a quorum of 2."
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

variable "backup_bucket_name" {
  type        = string
  description = "Private bucket the daily RDB backups go to (module.s3.private_bucket_name)"
}

variable "backup_bucket_arn" {
  type        = string
  description = "ARN of backup_bucket_name, for the nodes' IAM policy (module.s3.private_bucket_arn)"
}

variable "backup_prefix" {
  type        = string
  default     = "backups/redis"
  description = "Key prefix (\"folder\") for the RDB backups, without leading or trailing slash"
}

# variable "instance_type" {
#   type        = string
#   default     = "r8i.large"
#   description = "Same for all 3 nodes, because any node can become the master. r8i.large = 2 vCPU, 16 GiB."
# }

# variable "data_volume_size" {
#   type        = number
#   default     = 50
#   description = "Size in GiB of each node's gp3 volume for RDB snapshots and the AOF. Keep it at least 2-3x the RAM."
# }

variable "redis_version" {
  type        = string
  default     = "8.10"
  description = "Redis minor version installed from packages.redis.io (newest patch of it)"
}

variable "sentinel_master_name" {
  type        = string
  default     = "mymaster"
  description = "Name clients ask Sentinel for (\"get-master-addr-by-name\")"
}

variable "maxmemory_policy" {
  type        = string
  default     = "noeviction"
  description = "noeviction: refuse writes when full (Redis as a data store). allkeys-lru: drop old keys (Redis as a cache)."

  validation {
    condition     = contains(["noeviction", "allkeys-lru", "allkeys-lfu", "volatile-lru", "volatile-lfu", "volatile-ttl", "allkeys-random", "volatile-random"], var.maxmemory_policy)
    error_message = "maxmemory_policy must be a valid Redis eviction policy."
  }
}

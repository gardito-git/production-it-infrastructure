# Inputs this module accepts. The root module passes them in via the
# module "rabbitmq_cluster" block in main.tf.

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
  description = "VPC CIDR, allowed to connect to AMQP (5672) and the Prometheus metrics (15692)"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnets, one node per subnet/AZ (module.vpc.private_subnet_ids)"

  validation {
    condition     = length(var.private_subnet_ids) == 3
    error_message = "Exactly 3 private subnets are needed: one node per AZ, so quorum queues keep a majority (2 of 3) when an AZ fails."
  }
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "CIDRs of private_subnet_ids, same order. Used to give the nodes fixed IPs (.80)."
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key installed on every node for user \"ubuntu\""
}

variable "vpn_security_group_id" {
  type        = string
  description = "The VPN endpoint's security group (module.vpc.vpn_security_group_id): allowed to SSH in and to open the management UI"
}

variable "backup_bucket_name" {
  type        = string
  description = "Private bucket the daily definitions backups go to (module.s3.private_bucket_name)"
}

variable "backup_bucket_arn" {
  type        = string
  description = "ARN of backup_bucket_name, for the nodes' IAM policy (module.s3.private_bucket_arn)"
}

variable "backup_prefix" {
  type        = string
  default     = "backups/rabbitmq"
  description = "Key prefix (\"folder\") for the definitions backups, without leading or trailing slash"
}

variable "rabbitmq_version" {
  type        = string
  default     = "4.3"
  description = "RabbitMQ minor version installed from Team RabbitMQ's apt repository (newest patch of it). Erlang comes from the same place."

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.rabbitmq_version))
    error_message = "rabbitmq_version must be a minor version like \"4.3\"."
  }
}

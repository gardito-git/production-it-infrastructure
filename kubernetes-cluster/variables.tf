# Inputs this module accepts. The root module passes them in via the
# module "kubernetes_cluster" block in main.tf.

variable "project_name" {
  type        = string
  description = "Project name used in resource names and the cluster tag"
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

variable "instance_profile_name" {
  type        = string
  description = "IAM instance profile attached to every node (module.iam.node_instance_profile_name)"
}

variable "key_name" {
  type        = string
  default     = null
  description = "Optional EC2 key pair name. Leave null and use SSM Session Manager instead."
}

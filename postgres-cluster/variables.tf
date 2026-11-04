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


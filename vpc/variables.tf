# Inputs this module accepts. The root module passes them in via the
# module "vpc" block in terraform/main.tf.

variable "region" {
  type        = string
  description = "AWS region, used for AZ names and the S3 endpoint service name"
}

variable "project_name" {
  type        = string
  description = "Project name used in resource Name tags"
}

variable "environment" {
  type        = string
  description = "Environment name used in resource Name tags"
}

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC"
}

variable "vpn_client_names" {
  type        = set(string)
  description = "One VPN client certificate and .ovpn profile is created per name"
}

variable "vpn_client_cidr" {
  type        = string
  default     = "172.16.0.0/22"
  description = "IPs handed to connected VPN clients. Must not overlap the VPC or the Kubernetes pod/service CIDRs."
}

variable "vpn_subnet_keys" {
  type        = set(string)
  default     = ["a"]
  description = "Private subnets (a, b, c) the VPN endpoint is attached to. Each one costs extra per hour."
}

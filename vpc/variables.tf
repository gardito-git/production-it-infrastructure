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

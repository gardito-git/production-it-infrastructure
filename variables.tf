variable "region" {
  default     = "ap-southeast-1"
  type        = string
  description = "AWS region to deploy into"
}

variable "project_name" {
  default     = "example"
  type        = string
  description = "Project name used in tags and resource names"
}

variable "environment" {
  default     = "dev"
  type        = string
  description = "Deployment environment: dev, staging, beta, uat, live or production"

  # Rejects typos like "prod" or "Dev" at plan time instead of tagging them.
  validation {
    condition     = contains(["dev", "staging", "beta", "uat", "live", "production"], var.environment)
    error_message = "environment must be one of: dev, staging, beta, uat, live, production."
  }
}

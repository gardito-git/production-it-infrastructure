variable "region" {
  default     = "us-east-1"
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

variable "vpn_client_names" {
  type        = set(string)
  default     = ["admin"]
  description = "People who get a VPN profile, e.g. [\"gardito\", \"alice\"]"
}

variable "ssh_public_key" {
  type        = string
  description = "Your SSH public key (contents of ~/.ssh/id_ed25519.pub), installed on every node for user \"ubuntu\""

  validation {
    condition     = can(regex("^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521)) ", var.ssh_public_key))
    error_message = "ssh_public_key must be a public key line starting with ssh-ed25519, ssh-rsa or ecdsa-sha2-*. Never the private key."
  }
}

# Inputs this module accepts. The root module passes them in via the
# module "harbor" block in main.tf.

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
  description = "VPC for the security group and the private DNS zone (module.vpc.vpc_id)"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR. Requests from here (VPN users, Kubernetes, runners) get the full Harbor UI and API."
}

variable "public_subnet_id" {
  type        = string
  description = "Public subnet for the server, which has an Elastic IP (module.vpc.public_subnet_ids[0])"
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key installed on the server for user \"ubuntu\""
}

variable "vpn_security_group_id" {
  type        = string
  description = "The VPN endpoint's security group (module.vpc.vpn_security_group_id): allowed to SSH in"
}

variable "domain_name" {
  type        = string
  # default     = "harbor.example.com" # TO-DO
  description = "Harbor's name, e.g. \"harbor.example.com\". You point it at the Elastic IP in your public DNS; Let's Encrypt issues the certificate for it."

  validation {
    condition     = can(regex("^[a-z0-9-]+(\\.[a-z0-9-]+)+$", var.domain_name))
    error_message = "domain_name must be a lower-case hostname like \"harbor.example.com\"."
  }
}

variable "harbor_version" {
  type        = string
  default     = "2.15.4"
  description = "Harbor version installed at first boot. Change it together with harbor_installer_sha256."

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.harbor_version))
    error_message = "harbor_version must look like \"2.15.4\" (no leading v)."
  }
}

variable "harbor_installer_sha256" {
  type        = string
  default     = "eeb899cf7b626c925790adba87db9008dd1d73a693a72442651b5bdece9805c6"
  description = "SHA-256 of harbor-online-installer-v<harbor_version>.tgz, checked at first boot"

  validation {
    condition     = can(regex("^[0-9a-f]{64}$", var.harbor_installer_sha256))
    error_message = "harbor_installer_sha256 must be 64 lower-case hex characters."
  }
}

variable "snapshot_retention_count" {
  type        = number
  default     = 30
  description = "Daily snapshots of the data volume to keep"
}

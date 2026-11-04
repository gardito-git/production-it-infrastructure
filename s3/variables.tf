# Inputs this module accepts. The root module passes them in via the
# module "s3" block in main.tf.

variable "project_name" {
  type        = string
  description = "Project name used in bucket and resource names"
}

variable "environment" {
  type        = string
  description = "Environment name used in bucket and resource names"
}

variable "log_retention_days" {
  type        = number
  default     = 30
  description = "Objects under logs/ in the private bucket are deleted after this many days"
}

variable "backup_retention_days" {
  type        = number
  default     = 30
  description = "Objects under backups/ in the private bucket are deleted after this many days"
}

variable "noncurrent_version_retention_days" {
  type        = number
  default     = 30
  description = "Overwritten or deleted objects can be recovered for this many days (versioning)"
}

variable "cloudfront_price_class" {
  type        = string
  default     = "PriceClass_200"
  description = "CloudFront edge locations. PriceClass_200 includes Asia; PriceClass_100 is cheaper but only North America and Europe."
}

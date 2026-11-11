# Providers this module uses. The root module configures them.
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

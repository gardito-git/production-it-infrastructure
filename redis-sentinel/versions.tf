# Providers this module uses. The root module configures them; declaring them
# here tells Terraform where to download random from.
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    random = {
      source = "hashicorp/random"
    }
  }
}

# Providers this module uses. The root module configures them; declaring them
# here tells Terraform where to download tls from.
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    tls = {
      source = "hashicorp/tls"
    }
  }
}

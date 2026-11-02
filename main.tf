# Root module: run terraform from this folder. It calls the vpc module and
# passes the root variables into it.

module "vpc" {
  source = "./vpc"

  region       = var.region
  project_name = var.project_name
  environment  = var.environment
}

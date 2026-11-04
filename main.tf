# Root module: run terraform from this folder. It calls each module and wires
# one module's outputs into the next module's inputs.

module "vpc" {
  source = "./vpc"

  region       = var.region
  project_name = var.project_name
  environment  = var.environment

  vpn_client_names = var.vpn_client_names
}

module "iam" {
  source = "./iam"

  project_name = var.project_name
  environment  = var.environment
}

module "s3" {
  source = "./s3"

  project_name = var.project_name
  environment  = var.environment
}

module "kubernetes_cluster" {
  source = "./kubernetes-cluster"

  project_name = var.project_name
  environment  = var.environment

  vpc_id               = module.vpc.vpc_id
  vpc_cidr             = module.vpc.vpc_cidr
  private_subnet_ids   = module.vpc.private_subnet_ids
  private_subnet_cidrs = module.vpc.private_subnet_cidrs

  instance_profile_names = module.iam.node_instance_profile_names
  node_role_names        = module.iam.node_role_names

  # etcd snapshots -> s3://<private bucket>/backups/kubernetes/etcd/
  backup_bucket_name = module.s3.private_bucket_name
  backup_bucket_arn  = module.s3.private_bucket_arn

  ssh_public_key               = var.ssh_public_key
  ssh_source_security_group_id = module.vpc.vpn_security_group_id
}

module "postgres_cluster" {
  source = "./postgres-cluster"

  project_name = var.project_name
  environment  = var.environment

  vpc_id               = module.vpc.vpc_id
  vpc_cidr             = module.vpc.vpc_cidr
  private_subnet_ids   = module.vpc.private_subnet_ids
  private_subnet_cidrs = module.vpc.private_subnet_cidrs

  # pgBackRest -> s3://<private bucket>/backups/postgres/
  backup_bucket_name = module.s3.private_bucket_name
  backup_bucket_arn  = module.s3.private_bucket_arn

  ssh_public_key               = var.ssh_public_key
  ssh_source_security_group_id = module.vpc.vpn_security_group_id
}

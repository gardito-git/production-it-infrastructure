# Root module: run terraform from this folder. It calls each module and wires
# one module's outputs into the next module's inputs.

module "vpc" {
  source = "./vpc"

  region       = var.region
  project_name = var.project_name
  environment  = var.environment

  vpn_client_names = var.vpn_client_names
}

module "s3" {
  source = "./s3"

  project_name = var.project_name
  environment  = var.environment
}

module "web_server" {
  source = "./web-server"

  project_name = var.project_name
  environment  = var.environment

  vpc_id             = module.vpc.vpc_id
  vpc_cidr           = module.vpc.vpc_cidr
  private_subnet_ids = module.vpc.private_subnet_ids # internal ALB and servers

  ssh_public_key               = var.ssh_public_key
  ssh_source_security_group_id = module.vpc.vpn_security_group_id

  # Nginx reverse-proxies the Next.js frontend:
  #   CloudFront -> this internal ALB -> Nginx -> Next.js servers (fixed IPs .70)
  nextjs_upstreams    = module.nextjs_frontend.upstream_servers
  nextjs_server_names = module.nextjs_frontend.domain_names
}

module "kubernetes_cluster" {
  source = "./kubernetes-cluster"

  project_name = var.project_name
  environment  = var.environment

  vpc_id               = module.vpc.vpc_id
  vpc_cidr             = module.vpc.vpc_cidr
  private_subnet_ids   = module.vpc.private_subnet_ids
  private_subnet_cidrs = module.vpc.private_subnet_cidrs

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

module "redis_sentinel" {
  source = "./redis-sentinel"

  project_name = var.project_name
  environment  = var.environment

  vpc_id               = module.vpc.vpc_id
  vpc_cidr             = module.vpc.vpc_cidr
  private_subnet_ids   = module.vpc.private_subnet_ids
  private_subnet_cidrs = module.vpc.private_subnet_cidrs

  # Daily RDB backups -> s3://<private bucket>/backups/redis/
  backup_bucket_name = module.s3.private_bucket_name
  backup_bucket_arn  = module.s3.private_bucket_arn

  ssh_public_key               = var.ssh_public_key
  ssh_source_security_group_id = module.vpc.vpn_security_group_id
}
module "elasticsearch_cluster" {
  source = "./elasticsearch-cluster"

  project_name = var.project_name
  environment  = var.environment

  vpc_id               = module.vpc.vpc_id
  vpc_cidr             = module.vpc.vpc_cidr
  private_subnet_ids   = module.vpc.private_subnet_ids
  private_subnet_cidrs = module.vpc.private_subnet_cidrs

  # Daily snapshots -> s3://<private bucket>/backups/elasticsearch/
  backup_bucket_name = module.s3.private_bucket_name
  backup_bucket_arn  = module.s3.private_bucket_arn

  ssh_public_key        = var.ssh_public_key
  vpn_security_group_id = module.vpc.vpn_security_group_id # SSH and Kibana
}

module "nextjs_frontend" {
  source = "./nextjs-pm2-frontend"

  project_name = var.project_name
  environment  = var.environment

  vpc_id               = module.vpc.vpc_id
  private_subnet_ids   = module.vpc.private_subnet_ids
  private_subnet_cidrs = module.vpc.private_subnet_cidrs # fixed IPs .70

  # Pages go CloudFront -> web-server ALB (VPC origin) -> Nginx -> Next.js.
  origin_domain_name      = module.web_server.alb_dns_name
  origin_vpc_origin_id    = module.web_server.cloudfront_vpc_origin_id
  proxy_security_group_id = module.web_server.security_group_id

  ssh_public_key               = var.ssh_public_key
  ssh_source_security_group_id = module.vpc.vpn_security_group_id

  # The web team may upload releases and static files.
  deployer_group_name = module.s3.web_developers_group

  # Your own domain: ACM certificate in us-east-1 (see nextjs-pm2-frontend/README.md).
  domain_names        = []
  acm_certificate_arn = null
}

module "rabbitmq_cluster" {
  source = "./rabbitmq-cluster"

  project_name = var.project_name
  environment  = var.environment

  vpc_id               = module.vpc.vpc_id
  vpc_cidr             = module.vpc.vpc_cidr
  private_subnet_ids   = module.vpc.private_subnet_ids
  private_subnet_cidrs = module.vpc.private_subnet_cidrs # fixed IPs .80

  # Daily definitions backups -> s3://<private bucket>/backups/rabbitmq/
  backup_bucket_name = module.s3.private_bucket_name
  backup_bucket_arn  = module.s3.private_bucket_arn

  ssh_public_key        = var.ssh_public_key
  vpn_security_group_id = module.vpc.vpn_security_group_id # SSH and management UI
}

module "github_runner" {
  source = "./github-runner"

  project_name = var.project_name
  environment  = var.environment

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  # Your GitHub organization ("my-org") or one repository ("my-org/my-repo").
  github_scope = var.github_runner_scope

  # What jobs may do in AWS (through the runners' IAM role, no keys in GitHub).
  policy_arns = {
    frontend_deployer = module.nextjs_frontend.deployer_policy_arn # release.sh uploads
  }

  ssh_public_key               = var.ssh_public_key
  ssh_source_security_group_id = module.vpc.vpn_security_group_id
}

module "harbor" {
  source = "./harbor"

  project_name = var.project_name
  environment  = var.environment

  vpc_id           = module.vpc.vpc_id
  vpc_cidr         = module.vpc.vpc_cidr
  public_subnet_id = module.vpc.public_subnet_ids[0] # the server has an Elastic IP

  # Change to your real name. Then create its public A record (output harbor_public_ip).
  domain_name = "harbor.example.com"

  ssh_public_key        = var.ssh_public_key
  vpn_security_group_id = module.vpc.vpn_security_group_id
}

module "mongodb_cluster" {
  source = "./mongodb-cluster"

  project_name = var.project_name
  environment  = var.environment

  vpc_id               = module.vpc.vpc_id
  vpc_cidr             = module.vpc.vpc_cidr
  private_subnet_ids   = module.vpc.private_subnet_ids
  private_subnet_cidrs = module.vpc.private_subnet_cidrs # fixed IPs .100

  # Daily mongodump -> s3://<private bucket>/backups/mongodb/
  backup_bucket_name = module.s3.private_bucket_name
  backup_bucket_arn  = module.s3.private_bucket_arn

  ssh_public_key               = var.ssh_public_key
  ssh_source_security_group_id = module.vpc.vpn_security_group_id
}

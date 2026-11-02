# Project, Environment and ManagedBy tags come from default_tags in providers.tf,
# so each resource below only sets its own Name tag.

locals {
  name_suffix = "${var.project_name}-${var.environment}"

  # One entry per availability zone: key = AZ letter, value = subnet CIDR.
  # Adding a fourth AZ is a one-line change here; for_each does the rest.
  public_subnets = {
    a = "10.0.1.0/24"
    b = "10.0.2.0/24"
    c = "10.0.3.0/24"
  }

  private_subnets = {
    a = "10.0.101.0/24"
    b = "10.0.102.0/24"
    c = "10.0.103.0/24"
  }
}

resource "aws_vpc" "vpc_main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  instance_tenancy     = "default"

  tags = {
    Name = "vpc-${local.name_suffix}"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "igw_main" {
  vpc_id = aws_vpc.vpc_main.id

  tags = {
    Name = "igw-${local.name_suffix}"
  }
}

# Subnet Public
# for_each creates one subnet per map entry. Inside the block, each.key is the
# AZ letter ("a") and each.value is the CIDR ("10.0.1.0/24").
# Address one later as aws_subnet.public["a"].
resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id                  = aws_vpc.vpc_main.id
  cidr_block              = each.value
  availability_zone       = "${var.region}${each.key}"
  map_public_ip_on_launch = true

  tags = {
    Name = "subnet-public-${each.key}-${local.name_suffix}"
  }
}

# Subnet Private
resource "aws_subnet" "private" {
  for_each = local.private_subnets

  vpc_id            = aws_vpc.vpc_main.id
  cidr_block        = each.value
  availability_zone = "${var.region}${each.key}"

  tags = {
    Name = "subnet-private-${each.key}-${local.name_suffix}"
  }
}

# NAT Gateway with EIP
# A single NAT gateway keeps cost down for dev. For production, use one per AZ
# so private subnets keep internet access if one AZ goes down.
resource "aws_eip" "eip_nat" {
  domain = "vpc"

  tags = {
    Name = "eip-nat-${local.name_suffix}"
  }

  depends_on = [aws_internet_gateway.igw_main]
}

resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.eip_nat.id
  subnet_id     = aws_subnet.public["a"].id # NAT must live in a public subnet

  tags = {
    Name = "nat-gw-${local.name_suffix}"
  }

  depends_on = [aws_internet_gateway.igw_main]
}

# Routing: public
# All public subnets share one route table that sends 0.0.0.0/0 to the IGW.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vpc_main.id

  tags = {
    Name = "rt-public-${local.name_suffix}"
  }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw_main.id
}

# for_each over the subnets themselves: each.value is a whole aws_subnet object.
resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# Routing: private
# One route table per AZ, each sending 0.0.0.0/0 to the NAT gateway.
resource "aws_route_table" "private" {
  for_each = local.private_subnets

  vpc_id = aws_vpc.vpc_main.id

  tags = {
    Name = "rt-private-${each.key}-${local.name_suffix}"
  }
}

resource "aws_route" "private_nat" {
  for_each = aws_route_table.private

  route_table_id         = each.value.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gw.id
}

# Same keys ("a", "b", "c") on both maps, so each.key pairs subnet a with table a.
resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}

# Free gateway endpoint: S3 traffic bypasses the NAT gateway
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.vpc_main.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  # [for ...] builds a list of IDs from the for_each map. [*] only works with count.
  route_table_ids = [for rt in aws_route_table.private : rt.id]

  tags = {
    Name = "vpce-s3-${local.name_suffix}"
  }
}

# Values this module hands back to its caller, read as module.vpc.<name>.

output "vpc_id" {
  value = aws_vpc.vpc_main.id
}

output "vpc_cidr" {
  value = aws_vpc.vpc_main.cidr_block
}

output "public_subnet_ids" {
  value = [for s in aws_subnet.public : s.id]
}

# depends_on makes anything that uses these IDs (e.g. EC2 nodes) wait until the
# private subnets can actually reach the internet through the NAT gateway.
output "private_subnet_ids" {
  value = [for s in aws_subnet.private : s.id]

  depends_on = [
    aws_route.private_nat,
    aws_route_table_association.private,
  ]
}

# Same order as private_subnet_ids (a, b, c).
output "private_subnet_cidrs" {
  value = [for s in aws_subnet.private : s.cidr_block]
}

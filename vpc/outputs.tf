# Values this module hands back to its caller, read as module.vpc.<name>.

output "vpc_id" {
  value = aws_vpc.vpc_main.id
}

output "public_subnet_ids" {
  value = [for s in aws_subnet.public : s.id]
}

output "private_subnet_ids" {
  value = [for s in aws_subnet.private : s.id]
}

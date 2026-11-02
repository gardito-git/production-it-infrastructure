# The groups are created empty and every rule is its own resource.
# Inline ingress blocks can't be used here: control_plane allows traffic from
# worker and worker allows traffic from control_plane, so each group would
# depend on the other and Terraform fails with a dependency cycle.
# Separate rule resources only depend on the groups, which breaks the cycle.
# (Don't mix inline blocks and rule resources on one group; they overwrite each other.)

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

resource "aws_security_group" "control_plane" {
  name        = "${local.name_prefix}-control-plane"
  description = "Kubernetes control-plane nodes"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${local.name_prefix}-control-plane"
  }
}

resource "aws_security_group" "worker" {
  name        = "${local.name_prefix}-worker"
  description = "Kubernetes worker nodes"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${local.name_prefix}-worker"
  }
}

resource "aws_security_group" "etcd" {
  name        = "${local.name_prefix}-etcd"
  description = "External etcd members"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${local.name_prefix}-etcd"
  }
}

# Egress: all three groups may reach anywhere (package installs, image pulls, AWS APIs).
resource "aws_vpc_security_group_egress_rule" "all" {
  for_each = {
    control_plane = aws_security_group.control_plane.id
    worker        = aws_security_group.worker.id
    etcd          = aws_security_group.etcd.id
  }

  security_group_id = each.value
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "All outbound traffic"
}

# ICMP from the VPC on all three groups (ping, path MTU discovery).
resource "aws_vpc_security_group_ingress_rule" "icmp" {
  for_each = {
    control_plane = aws_security_group.control_plane.id
    worker        = aws_security_group.worker.id
    etcd          = aws_security_group.etcd.id
  }

  security_group_id = each.value
  ip_protocol       = "icmp"
  from_port         = -1
  to_port           = -1
  cidr_ipv4         = var.vpc_cidr
  description       = "ICMP from the VPC"
}

# Control plane

resource "aws_vpc_security_group_ingress_rule" "control_plane_api" {
  security_group_id = aws_security_group.control_plane.id
  ip_protocol       = "tcp"
  from_port         = 6443
  to_port           = 6443
  cidr_ipv4         = var.vpc_cidr
  description       = "kube-apiserver from the NLB, nodes and SSM port-forwards"
}

resource "aws_vpc_security_group_ingress_rule" "control_plane_self" {
  security_group_id            = aws_security_group.control_plane.id
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.control_plane.id
  description                  = "Control plane to control plane (kubelet, CNI, health checks)"
}

resource "aws_vpc_security_group_ingress_rule" "control_plane_from_worker" {
  security_group_id            = aws_security_group.control_plane.id
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.worker.id
  description                  = "Workers to control plane (kubelet, CNI)"
}

# Workers

resource "aws_vpc_security_group_ingress_rule" "worker_from_control_plane" {
  security_group_id            = aws_security_group.worker.id
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.control_plane.id
  description                  = "Control plane to workers (kubelet, webhooks, CNI)"
}

resource "aws_vpc_security_group_ingress_rule" "worker_self" {
  security_group_id            = aws_security_group.worker.id
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.worker.id
  description                  = "Worker to worker (pod network, kubelet)"
}

resource "aws_vpc_security_group_ingress_rule" "worker_nodeport" {
  security_group_id = aws_security_group.worker.id
  ip_protocol       = "tcp"
  from_port         = 30000
  to_port           = 32767
  cidr_ipv4         = var.vpc_cidr
  description       = "NodePort range from inside the VPC (load balancers)"
}

# etcd: clients (the API servers) only need 2379; 2380 is peer traffic between members.

resource "aws_vpc_security_group_ingress_rule" "etcd_client_from_control_plane" {
  security_group_id            = aws_security_group.etcd.id
  ip_protocol                  = "tcp"
  from_port                    = 2379
  to_port                      = 2379
  referenced_security_group_id = aws_security_group.control_plane.id
  description                  = "etcd client (2379) from the control plane"
}

resource "aws_vpc_security_group_ingress_rule" "etcd_peer" {
  security_group_id            = aws_security_group.etcd.id
  ip_protocol                  = "tcp"
  from_port                    = 2379
  to_port                      = 2380
  referenced_security_group_id = aws_security_group.etcd.id
  description                  = "etcd member to member (client and peer)"
}

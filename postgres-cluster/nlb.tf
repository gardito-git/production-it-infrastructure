# Internal NLB that always points at the right node:
#   port 5432 -> the current primary (read-write)
#   port 5433 -> the replicas (read-only)
# Each target group's health check asks Patroni's REST API what the node is:
# GET :8008/primary answers 200 only on the primary, /replica only on replicas.
# After a failover the health checks flip and the NLB follows within ~20 seconds,
# so applications keep using the same hostname.

resource "aws_lb" "postgres" {
  name                             = "${local.name_prefix}-pg"
  internal                         = true
  load_balancer_type               = "network"
  subnets                          = var.private_subnet_ids
  enable_cross_zone_load_balancing = true
}

locals {
  # One target group per role; the key is the Patroni endpoint it checks.
  pg_target_groups = {
    primary = { listener_port = 5432 }
    replica = { listener_port = 5433 }
  }
}

resource "aws_lb_target_group" "postgres" {
  for_each = local.pg_target_groups

  name        = "${local.name_prefix}-pg-${each.key}"
  port        = 5432
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = var.vpc_id

  # Close connections to a node as soon as it's removed, so clients reconnect
  # to the new primary instead of hanging on the old one.
  deregistration_delay   = 10
  connection_termination = true

  health_check {
    protocol            = "HTTP"
    port                = "8008"
    path                = "/${each.key}"
    interval            = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "postgres" {
  for_each = local.pg_target_groups

  load_balancer_arn = aws_lb.postgres.arn
  port              = each.value.listener_port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.postgres[each.key].arn
  }
}

# Every node is registered in both groups; the health checks decide where traffic goes.
resource "aws_lb_target_group_attachment" "postgres" {
  for_each = {
    for pair in setproduct(keys(local.pg_target_groups), range(3)) :
    "${pair[0]}-${pair[1]}" => { group = pair[0], node = pair[1] }
  }

  target_group_arn = aws_lb_target_group.postgres[each.value.group].arn
  target_id        = aws_instance.postgres[each.value.node].id
  port             = 5432
}

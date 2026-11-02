# Internal Network Load Balancer in front of the three kube-apiservers.
# This is kubeadm's controlPlaneEndpoint: nodes and kubectl always talk to the NLB,
# so losing one control-plane node doesn't take the API down.

resource "aws_lb" "api" {
  name                             = "${local.name_prefix}-api"
  internal                         = true
  load_balancer_type               = "network"
  subnets                          = var.private_subnet_ids
  enable_cross_zone_load_balancing = true
}

resource "aws_lb_target_group" "api" {
  name        = "${local.name_prefix}-api"
  port        = 6443
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = var.vpc_id

  # With client IP preservation on, a control-plane node calling the API through
  # the NLB can be routed back to itself and the connection fails (NLB hairpinning).
  # Off, traffic arrives from the NLB's VPC address, which the 6443 rule allows.
  preserve_client_ip = false

  # /readyz is readable without credentials and only returns 200 when the API
  # server can reach etcd, so a broken node is taken out of rotation.
  health_check {
    protocol            = "HTTPS"
    path                = "/readyz"
    port                = "traffic-port"
    interval            = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "api" {
  load_balancer_arn = aws_lb.api.arn
  port              = 6443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}

resource "aws_lb_target_group_attachment" "api" {
  count = length(aws_instance.control_plane)

  target_group_arn = aws_lb_target_group.api.arn
  target_id        = aws_instance.control_plane[count.index].id
  port             = 6443
}

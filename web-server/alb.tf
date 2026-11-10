# INTERNAL Application Load Balancer in front of the Nginx servers. It has no
# public IP: visitors come through CloudFront, which reaches it privately via
# a VPC origin (cloudfront.tf). Nobody can skip CloudFront.
#
#   CloudFront ──VPC origin──► ALB :80 (private) ──► web-1/2/3 :80 (Nginx)
#
# The ALB health-checks every server on /healthz and only sends requests to
# healthy ones, so a dead server drops out of rotation within ~30 seconds.
# TLS ends at CloudFront; this hop stays inside the VPC.

resource "aws_lb" "web" {
  name               = "${local.name_prefix}-web"
  internal           = true
  load_balancer_type = "application"
  subnets            = var.private_subnet_ids
  security_groups    = [aws_security_group.alb.id]

  # Reject requests with malformed headers instead of passing them to Nginx.
  drop_invalid_header_fields = true
  idle_timeout               = 60

  tags = {
    Name = "${local.name_prefix}-web"
  }
}

resource "aws_lb_target_group" "web" {
  name        = "${local.name_prefix}-web"
  port        = 80
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = var.vpc_id

  # Give in-flight requests 30 s to finish when a server is removed.
  deregistration_delay = 30

  health_check {
    path                = "/healthz"
    matcher             = "200"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_target_group_attachment" "web" {
  count = var.instance_count

  target_group_arn = aws_lb_target_group.web.arn
  target_id        = aws_instance.web_server[count.index].id
  port             = 80
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.web.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

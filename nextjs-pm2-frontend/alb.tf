# INTERNAL Application Load Balancer in the private subnets. It has no public
# IP: the only way in from the internet is CloudFront, through a VPC origin
# (cloudfront.tf). Nobody can skip CloudFront and hit the servers directly.
#
#   CloudFront ──VPC origin──► ALB :80 (private) ──► frontend-1/2/3 :3000 (PM2)
#
# The ALB health-checks every server and only sends requests to healthy ones,
# so a server that is down or mid-deploy drops out of rotation.

resource "aws_lb" "frontend" {
  name               = "${local.name_prefix}-frontend"
  internal           = true
  load_balancer_type = "application"
  subnets            = var.private_subnet_ids
  security_groups    = [aws_security_group.alb.id]

  drop_invalid_header_fields = true
  idle_timeout               = 60

  tags = {
    Name = "${local.name_prefix}-frontend"
  }
}

resource "aws_lb_target_group" "frontend" {
  name        = "${local.name_prefix}-frontend"
  port        = var.app_port
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = var.vpc_id

  # In-flight requests get 30 s to finish when a server is removed.
  deregistration_delay = 30

  health_check {
    path                = var.health_check_path
    matcher             = "200-399"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_target_group_attachment" "frontend" {
  count = var.instance_count

  target_group_arn = aws_lb_target_group.frontend.arn
  target_id        = aws_instance.frontend[count.index].id
  port             = var.app_port
}

# Plain HTTP is fine here: viewers use HTTPS to CloudFront, and the hop from
# CloudFront to this ALB runs privately inside the VPC.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.frontend.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}

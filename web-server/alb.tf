# Public Application Load Balancer in front of the web servers.
#
#   internet ──80/443──► ALB (public subnets) ──80──► web-1/2/3 (private subnets)
#
# The ALB health-checks every server on /healthz and only sends visitors to
# healthy ones, so a dead server drops out of rotation within ~30 seconds.
# It also terminates TLS (one ACM certificate, renewed by AWS) and adds
# X-Forwarded-For / X-Forwarded-Proto headers so Nginx knows the real client.

locals {
  https_enabled = var.certificate_arn != null
}

resource "aws_lb" "web" {
  name               = "${local.name_prefix}-web"
  internal           = false
  load_balancer_type = "application"
  subnets            = var.public_subnet_ids
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

# Port 80: forward to the servers, or redirect to HTTPS once a certificate is set.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.web.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = local.https_enabled ? "redirect" : "forward"
    target_group_arn = local.https_enabled ? null : aws_lb_target_group.web.arn

    dynamic "redirect" {
      for_each = local.https_enabled ? [1] : []

      content {
        protocol    = "HTTPS"
        port        = "443"
        status_code = "HTTP_301"
      }
    }
  }
}

# Port 443: only created when certificate_arn is set.
resource "aws_lb_listener" "https" {
  count = local.https_enabled ? 1 : 0

  load_balancer_arn = aws_lb.web.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = var.certificate_arn
  # TLS 1.2 and 1.3 only.
  ssl_policy = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

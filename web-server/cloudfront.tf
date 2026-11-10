# CloudFront's way into the private ALB: CloudFront places network interfaces
# in the private subnets and connects from there. Any CloudFront distribution
# in this account can use it as an origin by its ID (output
# cloudfront_vpc_origin_id); the Next.js frontend's distribution does.
resource "aws_cloudfront_vpc_origin" "web" {
  vpc_origin_endpoint_config {
    name                   = "${local.name_prefix}-web-alb"
    arn                    = aws_lb.web.arn
    http_port              = 80
    https_port             = 443
    origin_protocol_policy = "http-only"

    origin_ssl_protocols {
      items    = ["TLSv1.2"]
      quantity = 1
    }
  }

  tags = {
    Name = "${local.name_prefix}-web-alb"
  }
}

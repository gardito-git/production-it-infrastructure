# One CloudFront distribution, two origins:
#
#   browser ──HTTPS──► CloudFront
#                        ├─ /_next/static/*  ──► S3 (cached 1 year; files are hashed)
#                        ├─ /_next/image*    ──► web ALB ──► Nginx ──► Next.js (cached per url/width/quality)
#                        └─ everything else  ──► web ALB ──► Nginx ──► Next.js (not cached: SSR, API, server actions)
#
# The web ALB is the web-server module's internal ALB; CloudFront reaches it
# through that module's VPC origin. Nginx then proxies to the Next.js servers
# (web-server/scripts/nextjs-site.conf.tftpl).
#
# The servers then only render pages; the heavy, repetitive traffic (JS, CSS,
# fonts, optimized images) is answered by CloudFront's edge.

resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${local.name_prefix}-frontend"
  description                       = "CloudFront access to the ${local.name_prefix} frontend bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# AWS-managed policies.
data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

# Sends every viewer header, cookie and query string to Next.js, INCLUDING Host.
# Next.js needs the real Host: server actions reject requests whose Origin
# header doesn't match it ("Invalid Server Actions request").
data "aws_cloudfront_origin_request_policy" "all_viewer" {
  name = "Managed-AllViewer"
}

data "aws_cloudfront_response_headers_policy" "security_headers" {
  name = "Managed-SecurityHeadersPolicy"
}

# next/image: one cache entry per source image, width, quality and Accept
# (Next.js serves AVIF/WebP depending on what the browser accepts).
resource "aws_cloudfront_cache_policy" "next_image" {
  name        = "${local.name_prefix}-next-image"
  comment     = "next/image optimizer responses"
  min_ttl     = 0
  default_ttl = 86400    # 1 day when Next.js sends no Cache-Control
  max_ttl     = 31536000 # 1 year

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_brotli = false # images are already compressed
    enable_accept_encoding_gzip   = false

    cookies_config {
      cookie_behavior = "none"
    }

    headers_config {
      header_behavior = "whitelist"
      headers {
        items = ["Accept"]
      }
    }

    query_strings_config {
      query_string_behavior = "whitelist"
      query_strings {
        items = ["url", "w", "q"]
      }
    }
  }
}

resource "aws_cloudfront_distribution" "frontend" {
  enabled         = true
  comment         = "${local.name_prefix} Next.js frontend"
  is_ipv6_enabled = true
  http_version    = "http2and3"
  price_class     = var.cloudfront_price_class
  aliases         = var.domain_names

  origin {
    origin_id   = "web"
    domain_name = var.origin_domain_name

    vpc_origin_config {
      vpc_origin_id            = var.origin_vpc_origin_id
      origin_keepalive_timeout = 5
      origin_read_timeout      = 30
    }
  }

  origin {
    origin_id                = "static-s3"
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  # Hashed build output: safe to cache for a year at the edge and in browsers.
  ordered_cache_behavior {
    path_pattern               = "/_next/static/*"
    target_origin_id           = "static-s3"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = data.aws_cloudfront_cache_policy.caching_optimized.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security_headers.id
  }

  ordered_cache_behavior {
    path_pattern               = "/_next/image*"
    target_origin_id           = "web"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = false
    cache_policy_id            = aws_cloudfront_cache_policy.next_image.id
    origin_request_policy_id   = data.aws_cloudfront_origin_request_policy.all_viewer.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security_headers.id
  }

  # Pages, API routes, server actions: always fresh from Next.js. All methods,
  # because forms and server actions POST.
  default_cache_behavior {
    target_origin_id           = "web"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id   = data.aws_cloudfront_origin_request_policy.all_viewer.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security_headers.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # Free *.cloudfront.net certificate, or your own ACM certificate (us-east-1).
  viewer_certificate {
    cloudfront_default_certificate = var.acm_certificate_arn == null
    acm_certificate_arn            = var.acm_certificate_arn
    ssl_support_method             = var.acm_certificate_arn == null ? null : "sni-only"
    minimum_protocol_version       = var.acm_certificate_arn == null ? "TLSv1" : "TLSv1.2_2021"
  }

  tags = {
    Name = "${local.name_prefix}-frontend"
  }

  lifecycle {
    precondition {
      condition     = length(var.domain_names) == 0 || var.acm_certificate_arn != null
      error_message = "domain_names needs acm_certificate_arn: an ACM certificate in us-east-1 that covers those domains."
    }
  }
}

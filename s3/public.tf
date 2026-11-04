# Public static assets (js, css, images, fonts, media), served to the internet
# through CloudFront. The bucket itself stays PRIVATE: only this CloudFront
# distribution may read it (Origin Access Control). That gives HTTPS, caching
# close to users, cheaper data transfer than S3 directly, and no way to list
# or write the bucket from the internet.
#
#   browser ──HTTPS──► CloudFront (cache) ──signed request──► S3 bucket (private)
#
# Assets are at https://<cloudfront_domain>/<key>, e.g. /js/app.3f9a1c.js

resource "aws_s3_bucket" "public" {
  bucket        = "${local.name_prefix}-public-${local.account_id}"
  force_destroy = false

  tags = {
    Name = "${local.name_prefix}-public"
  }
}

resource "aws_s3_bucket_ownership_controls" "public" {
  bucket = aws_s3_bucket.public.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Public access stays blocked: CloudFront reads through the bucket policy
# below, which is scoped to one AWS service principal, not "public".
resource "aws_s3_bucket_public_access_block" "public" {
  bucket = aws_s3_bucket.public.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "public" {
  bucket = aws_s3_bucket.public.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Versioning lets the team roll back a bad deploy by restoring previous versions.
resource "aws_s3_bucket_versioning" "public" {
  bucket = aws_s3_bucket.public.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "public" {
  bucket = aws_s3_bucket.public.id

  rule {
    id     = "cleanup-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_retention_days
    }

    expiration {
      expired_object_delete_marker = true
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.public]
}

# CloudFront

resource "aws_cloudfront_origin_access_control" "public" {
  name                              = "${local.name_prefix}-public"
  description                       = "CloudFront access to the ${local.name_prefix} public bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# AWS-managed policies: cache well-compressed static files for a long time.
data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

# Adds HSTS, X-Content-Type-Options, X-Frame-Options and similar security headers.
data "aws_cloudfront_response_headers_policy" "security_headers" {
  name = "Managed-SecurityHeadersPolicy"
}

resource "aws_cloudfront_distribution" "public" {
  enabled         = true
  comment         = "${local.name_prefix} public assets"
  is_ipv6_enabled = true
  http_version    = "http2and3"
  price_class     = var.cloudfront_price_class

  origin {
    origin_id                = "public-s3"
    domain_name              = aws_s3_bucket.public.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.public.id
  }

  default_cache_behavior {
    target_origin_id           = "public-s3"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = data.aws_cloudfront_cache_policy.caching_optimized.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security_headers.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # Uses the free *.cloudfront.net certificate. For assets.example.com you need
  # an ACM certificate in us-east-1 and `aliases` (see the README TO-DO).
  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name = "${local.name_prefix}-public"
  }
}

# Only this distribution may read objects, proven by the SourceArn condition.
data "aws_iam_policy_document" "public" {
  statement {
    sid       = "AllowCloudFrontRead"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.public.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.public.arn]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.public.arn, "${aws_s3_bucket.public.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "public" {
  bucket = aws_s3_bucket.public.id
  policy = data.aws_iam_policy_document.public.json

  depends_on = [aws_s3_bucket_public_access_block.public]
}

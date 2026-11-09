# One private bucket for the frontend, two "folders":
#   _next/static/   hashed JS/CSS/fonts from `next build`, served by CloudFront
#   releases/       <version>.tar.gz server bundles + CURRENT (the live version),
#                   downloaded by the servers; never reachable from the internet
#
# Static files are kept for every version ever released (no --delete): during a
# rolling deploy some visitors still have the old HTML, and it must still find
# its old JS chunks. They're small and hashed, so they never collide.

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  account_id  = data.aws_caller_identity.current.account_id
}

resource "aws_s3_bucket" "frontend" {
  # Bucket names are global across all AWS accounts; the account ID avoids collisions.
  bucket        = "${local.name_prefix}-frontend-${local.account_id}"
  force_destroy = false

  tags = {
    Name = "${local.name_prefix}-frontend"
  }
}

resource "aws_s3_bucket_ownership_controls" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Versioning: an accidentally re-uploaded release can be restored.
resource "aws_s3_bucket_versioning" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  rule {
    id     = "cleanup-old-versions"
    status = "Enabled"

    filter {}

    # Overwritten objects (mostly releases/CURRENT) are kept 30 days.
    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    expiration {
      expired_object_delete_marker = true
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.frontend]
}

data "aws_iam_policy_document" "frontend_bucket" {
  # CloudFront may read _next/static/ only; releases/ stays private.
  statement {
    sid       = "AllowCloudFrontReadStatic"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.frontend.arn}/_next/static/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.frontend.arn]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.frontend.arn, "${aws_s3_bucket.frontend.arn}/*"]

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

resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  policy = data.aws_iam_policy_document.frontend_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.frontend]
}

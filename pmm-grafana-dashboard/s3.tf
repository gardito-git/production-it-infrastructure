# Logs live in S3 (cheap, no disk to grow): Loki writes compressed chunks and
# its index here and deletes them itself after var.retention_days (compactor).
# A bucket of its own, because Loki owns its whole layout.

data "aws_caller_identity" "current" {}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

resource "aws_s3_bucket" "loki" {
  # Bucket names are global across all AWS accounts; the account ID avoids collisions.
  bucket        = "${local.name_prefix}-loki-${data.aws_caller_identity.current.account_id}"
  force_destroy = false

  tags = {
    Name = "${local.name_prefix}-loki"
  }
}

resource "aws_s3_bucket_ownership_controls" "loki" {
  bucket = aws_s3_bucket.loki.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "loki" {
  bucket = aws_s3_bucket.loki.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "loki" {
  bucket = aws_s3_bucket.loki.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# No age-based expiry here: Loki's compactor deletes old logs together with
# their index entries. An S3 rule could delete chunks Loki still points to.
resource "aws_s3_bucket_lifecycle_configuration" "loki" {
  bucket = aws_s3_bucket.loki.id

  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "loki_bucket" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.loki.arn, "${aws_s3_bucket.loki.arn}/*"]

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

resource "aws_s3_bucket_policy" "loki" {
  bucket = aws_s3_bucket.loki.id
  policy = data.aws_iam_policy_document.loki_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.loki]
}

# pgBackRest repository: weekly full + daily differential backups, plus every
# WAL file, so the database can be restored to any second within the retention.
# The traffic stays inside AWS through the VPC's free S3 gateway endpoint.

resource "aws_s3_bucket" "backups" {
  bucket_prefix = "${local.name_prefix}-pg-backups-"

  # Deliberately false: `terraform destroy` fails while backups exist, instead
  # of silently deleting them. Empty the bucket by hand if you really mean it.
  force_destroy = false
}

resource "aws_s3_bucket_public_access_block" "backups" {
  bucket = aws_s3_bucket.backups.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# pgBackRest deletes expired backups itself (repo1-retention-full); this only
# cleans up uploads interrupted halfway, which S3 would otherwise keep billing.
resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "backups_tls_only" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.backups.arn, "${aws_s3_bucket.backups.arn}/*"]

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

resource "aws_s3_bucket_policy" "backups" {
  bucket = aws_s3_bucket.backups.id
  policy = data.aws_iam_policy_document.backups_tls_only.json

  depends_on = [aws_s3_bucket_public_access_block.backups]
}

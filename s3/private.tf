# General-purpose private bucket: logs, backups, uploads, anything that must
# never be public. Organise it with key prefixes ("folders"):
#   logs/      deleted after var.log_retention_days
#   backups/   deleted after var.backup_retention_days, e.g. backups/kubernetes/etcd/
#   tmp/       deleted after 7 days
#   anything else (uploads/, web/, ...) is kept until someone deletes it.
#
# S3 has no real folders: a prefix appears as soon as an object is written under it,
# so there is nothing to create here in advance.

data "aws_caller_identity" "current" {}

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  # Bucket names are global across ALL AWS accounts. Adding the account ID
  # makes a collision with somebody else's bucket practically impossible.
  account_id = data.aws_caller_identity.current.account_id
}

resource "aws_s3_bucket" "private" {
  bucket = "${local.name_prefix}-private-${local.account_id}"

  # `terraform destroy` fails while the bucket holds objects, instead of
  # deleting backups silently. Empty it by hand if you really mean it.
  force_destroy = false

  tags = {
    Name = "${local.name_prefix}-private"
  }
}

# ACLs disabled: only IAM and bucket policies decide access. This is the AWS
# default for new buckets and the reason ACL settings are not used anywhere here.
resource "aws_s3_bucket_ownership_controls" "private" {
  bucket = aws_s3_bucket.private.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "private" {
  bucket = aws_s3_bucket.private.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "private" {
  bucket = aws_s3_bucket.private.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Versioning keeps the previous copy when an object is overwritten or deleted,
# so a bad script or an accidental `aws s3 rm --recursive` can be undone.
# Old versions are cleaned up by the lifecycle rules below.
resource "aws_s3_bucket_versioning" "private" {
  bucket = aws_s3_bucket.private.id

  versioning_configuration {
    status = "Enabled"
  }
}

locals {
  # prefix => days until objects under it are deleted
  private_expiring_prefixes = {
    "logs/"    = var.log_retention_days
    "backups/" = var.backup_retention_days
    "tmp/"     = 7
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "private" {
  bucket = aws_s3_bucket.private.id

  dynamic "rule" {
    for_each = local.private_expiring_prefixes

    content {
      id     = "expire-${trimsuffix(rule.key, "/")}"
      status = "Enabled"

      filter {
        prefix = rule.key
      }

      expiration {
        days = rule.value
      }
    }
  }

  # Applies to the whole bucket: recoverable old versions, then gone for good.
  rule {
    id     = "cleanup-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_retention_days
    }

    # Remove "delete markers" left behind once all versions of an object are gone.
    expiration {
      expired_object_delete_marker = true
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # Lifecycle rules apply to versions only once versioning is on.
  depends_on = [aws_s3_bucket_versioning.private]
}

data "aws_iam_policy_document" "private" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.private.arn, "${aws_s3_bucket.private.arn}/*"]

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

resource "aws_s3_bucket_policy" "private" {
  bucket = aws_s3_bucket.private.id
  policy = data.aws_iam_policy_document.private.json

  depends_on = [aws_s3_bucket_public_access_block.private]
}

# Dedicated, private bucket for image layers. Harbor writes to it with its
# built-in S3 storage driver, authenticated by the server's IAM role. It holds
# only image data: users, projects and tags are in PostgreSQL on the data volume.

data "aws_caller_identity" "current" {}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

resource "aws_s3_bucket" "harbor" {
  # Bucket names are global across all AWS accounts.
  bucket = "${local.name_prefix}-harbor"

  # `terraform destroy` fails while images exist, instead of deleting them silently.
  force_destroy = false

  tags = {
    Name = "${local.name_prefix}-harbor"
  }
}

resource "aws_s3_bucket_ownership_controls" "harbor" {
  bucket = aws_s3_bucket.harbor.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "harbor" {
  bucket = aws_s3_bucket.harbor.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "harbor" {
  bucket = aws_s3_bucket.harbor.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# No versioning: Harbor's garbage collection deletes unused layers to save
# money, and versioning would keep paying for them.
resource "aws_s3_bucket_lifecycle_configuration" "harbor" {
  bucket = aws_s3_bucket.harbor.id

  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"

    filter {}

    # Interrupted `docker push` uploads would otherwise be billed forever.
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "harbor_bucket" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.harbor.arn, "${aws_s3_bucket.harbor.arn}/*"]

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

resource "aws_s3_bucket_policy" "harbor" {
  bucket = aws_s3_bucket.harbor.id
  policy = data.aws_iam_policy_document.harbor_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.harbor]
}

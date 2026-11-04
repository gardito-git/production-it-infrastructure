data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_s3_bucket" "private" {
  bucket = "${var.project_name}-bucket"
  force_destroy = false

  tags = {
    Name        = "${var.project_name}-bucket"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "private" {
  bucket = aws_s3_bucket.private.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "private" {
  bucket = aws_s3_bucket.private.id

  rule {
    id      = "expire-objects"
    enabled = true

    expiration {
      days = 30
    }
  }
}

resource "aws_s3_bucket_acl" "private" {
  bucket = aws_s3_bucket.private.id
  acl    = "private"
}

resource "aws_s3_bucket_versioning" "private" {
  bucket = aws_s3_bucket.private.id

  versioning_configuration {
    status = "Disabled"
  }
}

resource "aws_s3_bucket_public_access_block" "private" {
  bucket = aws_s3_bucket.private.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# For Postgres
resource "aws_s3_object" "postgres" {
  bucket = aws_s3_bucket.private.id
  key    = "postgres/backup"
  acl    = "private"
}

# For Kubernetes
resource "aws_s3_object" "kubernetes" {
  bucket = aws_s3_bucket.private.id
  key    = "kubernetes/backup"
  acl    = "private"
}

# For Backend
resource "aws_s3_object" "backend" {
   for_each = toset([
    "logs/",
    "uploads/",
    "backups/"
    # something else? Add it here. Each of these is a folder in the bucket, and will be created as an empty object with a trailing slash.
  ])

  bucket = aws_s3_bucket.private.id
  key    = each.value
  acl    = "private"
}
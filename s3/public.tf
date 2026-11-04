# This is CDN public bucket for static assets. It is not private, and it is not encrypted. It is used to serve static assets for the web application.

resource "aws_s3_bucket" "public" {
  bucket = "${var.project_name}-public"
  force_destroy = false

  tags = {
    Name        = "${var.project_name}-public"
  }
}

resource "aws_s3_bucket_acl" "public" {
  bucket = aws_s3_bucket.public.id
  acl    = "public-read"
}

resource "aws_s3_bucket_versioning" "public" {
  bucket = aws_s3_bucket.public.id

  versioning_configuration {
    status = "Disabled"
  }
}

resource "aws_s3_bucket_public_access_block" "public" {
  bucket = aws_s3_bucket.public.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "public" {
  bucket = aws_s3_bucket.public.id
  policy = data.aws_iam_policy_document.public.json
}

# For Frontend
resource "aws_s3_object" "frontend" {
   for_each = toset([
    "logos/",
    "svgs/",
    "css/",
    "js/",
    "images/",
    "fonts/",
    "media/",
    "logs/",
    "uploads/",
    "backups/"
    # something else? Add it here. Each of these is a folder in the bucket, and will be created as an empty object with a trailing slash.
  ])

  bucket = aws_s3_bucket.public.id
  key    = each.value
  acl    = "public-read"
}
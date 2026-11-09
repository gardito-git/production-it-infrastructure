# Two sets of permissions:
#   servers:    download releases/ and record the live version (releases/CURRENT)
#   deployers:  upload releases/ and _next/static/, clear the CloudFront cache
# Nobody here may delete objects: old static files must stay for old HTML.

# Servers

data "aws_iam_policy_document" "assume_ec2" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "frontend" {
  name               = "${local.name_prefix}-frontend"
  assume_role_policy = data.aws_iam_policy_document.assume_ec2.json
}

data "aws_iam_policy_document" "frontend" {
  statement {
    sid       = "DownloadReleases"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.frontend.arn}/releases/*"]
  }

  statement {
    sid       = "RecordLiveVersion"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.frontend.arn}/releases/CURRENT"]
  }
}

resource "aws_iam_role_policy" "frontend" {
  name   = "releases"
  role   = aws_iam_role.frontend.id
  policy = data.aws_iam_policy_document.frontend.json
}

resource "aws_iam_instance_profile" "frontend" {
  name = "${local.name_prefix}-frontend"
  role = aws_iam_role.frontend.name
}

# Deployers (people or CI)

data "aws_iam_policy_document" "deployer" {
  statement {
    sid       = "ListBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.frontend.arn]
  }

  statement {
    sid     = "UploadReleases"
    actions = ["s3:GetObject", "s3:PutObject"]
    resources = [
      "${aws_s3_bucket.frontend.arn}/releases/*",
      "${aws_s3_bucket.frontend.arn}/_next/static/*",
    ]
  }

  statement {
    sid       = "InvalidateCdnCache"
    actions   = ["cloudfront:CreateInvalidation", "cloudfront:GetInvalidation", "cloudfront:ListInvalidations"]
    resources = [aws_cloudfront_distribution.frontend.arn]
  }
}

resource "aws_iam_policy" "deployer" {
  name        = "${local.name_prefix}-frontend-deployer"
  description = "Upload Next.js releases and static files; invalidate the frontend CloudFront cache"
  policy      = data.aws_iam_policy_document.deployer.json
}

resource "aws_iam_group_policy_attachment" "deployer" {
  count = var.deployer_group_name == null ? 0 : 1

  group      = var.deployer_group_name
  policy_arn = aws_iam_policy.deployer.arn
}

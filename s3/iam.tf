# IAM group for the web team. Add people to it (IAM users, or map it from
# IAM Identity Center); everyone in it can:
#   - deploy assets: upload/delete in the public bucket and clear the CloudFront cache
#   - keep their own files in the private bucket under web/ (e.g. backups)
# They can't touch anything else in the private bucket (logs/, backups/, ...).

resource "aws_iam_group" "web_developers" {
  name = "${local.name_prefix}-web-developers"
}

data "aws_iam_policy_document" "web_developers" {
  statement {
    sid       = "ListPublicBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.public.arn]
  }

  statement {
    sid       = "DeployPublicAssets"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.public.arn}/*"]
  }

  statement {
    sid       = "InvalidateCdnCache"
    actions   = ["cloudfront:CreateInvalidation", "cloudfront:GetInvalidation", "cloudfront:ListInvalidations"]
    resources = [aws_cloudfront_distribution.public.arn]
  }

  # s3:prefix limits listing to web/, so the rest of the bucket's keys stay hidden.
  statement {
    sid       = "ListOwnPrivatePrefix"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.private.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["web/", "web/*"]
    }
  }

  statement {
    sid       = "ReadWriteOwnPrivatePrefix"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:GetObjectVersion"]
    resources = ["${aws_s3_bucket.private.arn}/web/*"]
  }
}

resource "aws_iam_policy" "web_developers" {
  name        = "${local.name_prefix}-web-developers"
  description = "Deploy public assets and use the web/ prefix of the private bucket"
  policy      = data.aws_iam_policy_document.web_developers.json
}

resource "aws_iam_group_policy_attachment" "web_developers" {
  group      = aws_iam_group.web_developers.name
  policy_arn = aws_iam_policy.web_developers.arn
}

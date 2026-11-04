# The nodes' IAM role lives in this module (not ../iam) because every permission
# it has is about this module's own secret and backup prefix.

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "postgres" {
  name               = "${local.name_prefix}-postgres"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_instance_profile" "postgres" {
  name = "${local.name_prefix}-postgres"
  role = aws_iam_role.postgres.name
}

data "aws_iam_policy_document" "postgres" {
  statement {
    sid       = "ReadOwnSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.postgres.arn]
  }

  # pgBackRest lists, reads, writes and (for retention) deletes backup files,
  # only under its own prefix of the shared private bucket.
  statement {
    sid       = "BackupPrefixList"
    actions   = ["s3:ListBucket"]
    resources = [var.backup_bucket_arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = [var.backup_prefix, "${var.backup_prefix}/*"]
    }
  }

  statement {
    sid       = "BackupPrefixObjects"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${var.backup_bucket_arn}/${var.backup_prefix}/*"]
  }
}

resource "aws_iam_role_policy" "postgres" {
  name   = "postgres-cluster"
  role   = aws_iam_role.postgres.name
  policy = data.aws_iam_policy_document.postgres.json
}

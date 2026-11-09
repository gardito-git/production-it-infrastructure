# The nodes' IAM role: read the password, and upload backups to their own prefix.

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "redis" {
  name               = "${local.name_prefix}-redis"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_instance_profile" "redis" {
  name = "${local.name_prefix}-redis"
  role = aws_iam_role.redis.name
}

data "aws_iam_policy_document" "redis" {
  statement {
    sid       = "ReadOwnSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.redis.arn]
  }

  # Upload only: a compromised node can't read or delete older backups.
  statement {
    sid       = "UploadBackups"
    actions   = ["s3:PutObject"]
    resources = ["${var.backup_bucket_arn}/${var.backup_prefix}/*"]
  }
}

resource "aws_iam_role_policy" "redis" {
  name   = "redis-sentinel"
  role   = aws_iam_role.redis.name
  policy = data.aws_iam_policy_document.redis.json
}

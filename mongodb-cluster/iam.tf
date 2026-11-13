# The nodes' IAM role: read the secret, and upload backups to their own prefix.

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "mongodb" {
  name               = "${local.name_prefix}-mongodb"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_instance_profile" "mongodb" {
  name = "${local.name_prefix}-mongodb"
  role = aws_iam_role.mongodb.name
}

data "aws_iam_policy_document" "mongodb" {
  statement {
    sid       = "ReadOwnSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.mongodb.arn]
  }

  # Upload only: a compromised node can't read or delete older backups.
  # (Large uploads are multipart; PutObject covers every part.)
  statement {
    sid       = "UploadBackups"
    actions   = ["s3:PutObject"]
    resources = ["${var.backup_bucket_arn}/${var.backup_prefix}/*"]
  }
}

resource "aws_iam_role_policy" "mongodb" {
  name   = "mongodb-cluster"
  role   = aws_iam_role.mongodb.name
  policy = data.aws_iam_policy_document.mongodb.json
}

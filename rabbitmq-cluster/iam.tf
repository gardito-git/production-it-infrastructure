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

resource "aws_iam_role" "rabbitmq" {
  name               = "${local.name_prefix}-rabbitmq"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_instance_profile" "rabbitmq" {
  name = "${local.name_prefix}-rabbitmq"
  role = aws_iam_role.rabbitmq.name
}

data "aws_iam_policy_document" "rabbitmq" {
  statement {
    sid       = "ReadOwnSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.rabbitmq.arn]
  }

  # Upload only: a compromised node can't read or delete older backups.
  statement {
    sid       = "UploadBackups"
    actions   = ["s3:PutObject"]
    resources = ["${var.backup_bucket_arn}/${var.backup_prefix}/*"]
  }
}

resource "aws_iam_role_policy" "rabbitmq" {
  name   = "rabbitmq-cluster"
  role   = aws_iam_role.rabbitmq.name
  policy = data.aws_iam_policy_document.rabbitmq.json
}

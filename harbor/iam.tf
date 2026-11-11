# The server's IAM role: read its passwords, and store image layers in its own
# bucket. Harbor's containers get these credentials through the instance
# metadata service, so no AWS keys are stored in Harbor.

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "harbor" {
  name               = "${local.name_prefix}-harbor"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_instance_profile" "harbor" {
  name = "${local.name_prefix}-harbor"
  role = aws_iam_role.harbor.name
}

data "aws_iam_policy_document" "harbor" {
  statement {
    sid       = "ReadOwnSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.harbor.arn]
  }

  statement {
    sid       = "ListRegistryBucket"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation", "s3:ListBucketMultipartUploads"]
    resources = [aws_s3_bucket.harbor.arn]
  }

  statement {
    sid = "ReadWriteImageLayers"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListMultipartUploadParts",
      "s3:AbortMultipartUpload",
    ]
    resources = ["${aws_s3_bucket.harbor.arn}/*"]
  }
}

resource "aws_iam_role_policy" "harbor" {
  name   = "harbor"
  role   = aws_iam_role.harbor.name
  policy = data.aws_iam_policy_document.harbor.json
}

# Daily snapshots of the data volume (compute.tf) are taken by AWS Data
# Lifecycle Manager, which needs its own role.
data "aws_iam_policy_document" "dlm_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["dlm.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "dlm" {
  name               = "${local.name_prefix}-harbor-dlm"
  assume_role_policy = data.aws_iam_policy_document.dlm_assume.json
}

resource "aws_iam_role_policy_attachment" "dlm" {
  role       = aws_iam_role.dlm.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSDataLifecycleManagerServiceRole"
}

# Two roles: Elasticsearch nodes read the secret and write snapshots to S3;
# Kibana only reads the secret.

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

locals {
  es_roles = toset(["elasticsearch", "kibana"])
}

resource "aws_iam_role" "node" {
  for_each = local.es_roles

  name               = "${local.name_prefix}-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_instance_profile" "node" {
  for_each = local.es_roles

  name = "${local.name_prefix}-${each.key}"
  role = aws_iam_role.node[each.key].name
}

data "aws_iam_policy_document" "read_secret" {
  statement {
    sid       = "ReadOwnSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.elasticsearch.arn]
  }
}

resource "aws_iam_role_policy" "read_secret" {
  for_each = local.es_roles

  name   = "read-elasticsearch-secret"
  role   = aws_iam_role.node[each.key].name
  policy = data.aws_iam_policy_document.read_secret.json
}

# The S3 snapshot repository: every master and data node reads and writes it
# (data nodes copy shard files, masters write the snapshot metadata).
data "aws_iam_policy_document" "snapshots" {
  statement {
    sid       = "ListSnapshotPrefix"
    actions   = ["s3:ListBucket"]
    resources = [var.backup_bucket_arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = [var.backup_prefix, "${var.backup_prefix}/*"]
    }
  }

  statement {
    sid       = "MultipartUploads"
    actions   = ["s3:ListBucketMultipartUploads", "s3:GetBucketLocation"]
    resources = [var.backup_bucket_arn]
  }

  statement {
    sid = "SnapshotObjects"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
    ]
    resources = ["${var.backup_bucket_arn}/${var.backup_prefix}/*"]
  }
}

resource "aws_iam_role_policy" "snapshots" {
  name   = "elasticsearch-snapshots"
  role   = aws_iam_role.node["elasticsearch"].name
  policy = data.aws_iam_policy_document.snapshots.json
}

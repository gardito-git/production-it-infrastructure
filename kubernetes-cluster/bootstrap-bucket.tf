# Private bucket the nodes use to hand bootstrap artifacts to each other:
#   etcd/<ip>.tar.gz                  etcd member certs        etcd-1 -> etcd-2, etcd-3
#   control-plane/etcd-client.tar.gz  API server etcd client   etcd-1 -> control-plane-1
#   join/control-plane.sh             join command + cert key  control-plane-1 -> control-plane-2, -3
#   join/worker.sh                    join command             control-plane-1 -> workers
# These are secrets. Objects expire after 1 day; delete them once the cluster is up
# (see scripts/README.md).

resource "aws_s3_bucket" "bootstrap" {
  bucket_prefix = "${local.name_prefix}-k8s-bootstrap-"
  force_destroy = true # only holds short-lived bootstrap files
}

resource "aws_s3_bucket_public_access_block" "bootstrap" {
  bucket = aws_s3_bucket.bootstrap.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "bootstrap" {
  bucket = aws_s3_bucket.bootstrap.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "bootstrap" {
  bucket = aws_s3_bucket.bootstrap.id

  rule {
    id     = "expire-bootstrap-secrets"
    status = "Enabled"

    filter {}

    expiration {
      days = 1
    }
  }
}

data "aws_iam_policy_document" "bootstrap_bucket_tls_only" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.bootstrap.arn, "${aws_s3_bucket.bootstrap.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "bootstrap" {
  bucket = aws_s3_bucket.bootstrap.id
  policy = data.aws_iam_policy_document.bootstrap_bucket_tls_only.json

  depends_on = [aws_s3_bucket_public_access_block.bootstrap]
}

# Each node type may only touch the keys it needs.
locals {
  bucket_objects = "${aws_s3_bucket.bootstrap.arn}/"

  bootstrap_access = {
    etcd = {
      read  = ["etcd/*"]
      write = ["etcd/*", "control-plane/etcd-client.tar.gz"]
    }
    control-plane = {
      read  = ["control-plane/*", "join/control-plane.sh"]
      write = ["join/*"]
    }
    worker = {
      read  = ["join/worker.sh"]
      write = []
    }
  }
}

data "aws_iam_policy_document" "bootstrap_access" {
  for_each = local.bootstrap_access

  statement {
    sid       = "Read"
    actions   = ["s3:GetObject"]
    resources = [for key in each.value.read : "${local.bucket_objects}${key}"]
  }

  dynamic "statement" {
    for_each = length(each.value.write) > 0 ? [1] : []

    content {
      sid       = "Write"
      actions   = ["s3:PutObject"]
      resources = [for key in each.value.write : "${local.bucket_objects}${key}"]
    }
  }
}

resource "aws_iam_role_policy" "bootstrap_access" {
  for_each = local.bootstrap_access

  name   = "k8s-bootstrap-bucket"
  role   = aws_iam_role.node[each.key].name
  policy = data.aws_iam_policy_document.bootstrap_access[each.key].json
}

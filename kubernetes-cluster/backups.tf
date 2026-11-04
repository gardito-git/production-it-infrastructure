# etcd snapshots go to the shared private bucket (s3 module), under
# <backup_prefix>/etcd/ (default backups/kubernetes/etcd/). The bucket's lifecycle
# rule deletes them after its backup_retention_days.
#
# Only the etcd nodes may write there, and only under that prefix. They can't
# read or delete backups, so a compromised node can't wipe the history.

data "aws_iam_policy_document" "etcd_backups" {
  statement {
    sid       = "UploadEtcdSnapshots"
    actions   = ["s3:PutObject"]
    resources = ["${var.backup_bucket_arn}/${var.backup_prefix}/etcd/*"]
  }
}

resource "aws_iam_role_policy" "etcd_backups" {
  name   = "etcd-backups"
  role   = aws_iam_role.node["etcd"].name
  policy = data.aws_iam_policy_document.etcd_backups.json
}

resource "iam_role" "rds" {
  name = "${var.project_name}-rds-role"

  assume_role_policy = data.aws_iam_policy_document.rds_assume_role_policy.json
}

resource "iam_role_policy" "rds" {
  name = "${var.project_name}-rds-policy"
  role = iam_role.rds.id

  policy = data.aws_iam_policy_document.rds_policy.json
}

resource "iam_role" "rds_backup" {
  name = "${var.project_name}-rds-backup-role"

  assume_role_policy = data.aws_iam_policy_document.rds_backup_assume_role_policy.json
}

resource "iam_role_policy" "rds_backup" {
  name = "${var.project_name}-rds-backup-policy"
  role = iam_role.rds_backup.id

  policy = data.aws_iam_policy_document.rds_backup_policy.json
}

resource "iam_role" "rds_restore" {
  name = "${var.project_name}-rds-restore-role"

  assume_role_policy = data.aws_iam_policy_document.rds_restore_assume_role_policy.json
}

resource "iam_role_policy" "rds_restore" {
  name = "${var.project_name}-rds-restore-policy"
  role = iam_role.rds_restore.id

  policy = data.aws_iam_policy_document.rds_restore_policy.json
}

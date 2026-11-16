data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# The monitoring server: read its passwords, publish the agent token, and let
# Loki store logs in its bucket (through the instance role, no AWS keys).
resource "aws_iam_role" "monitoring" {
  name               = "${local.name_prefix}-monitoring"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_instance_profile" "monitoring" {
  name = "${local.name_prefix}-monitoring"
  role = aws_iam_role.monitoring.name
}

data "aws_iam_policy_document" "monitoring" {
  statement {
    sid       = "ReadSecrets"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.admin.arn, aws_secretsmanager_secret.agent_token.arn, aws_secretsmanager_secret.github.arn]
  }

  statement {
    sid       = "PublishAgentToken"
    actions   = ["secretsmanager:PutSecretValue"]
    resources = [aws_secretsmanager_secret.agent_token.arn]
  }

  statement {
    sid       = "LokiBucket"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.loki.arn]
  }

  statement {
    sid       = "LokiObjects"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.loki.arn}/*"]
  }
}

resource "aws_iam_role_policy" "monitoring" {
  name   = "monitoring"
  role   = aws_iam_role.monitoring.name
  policy = data.aws_iam_policy_document.monitoring.json
}

# Every monitored server's role gets this: read the agent token, nothing else.
# Other modules attach it through their `monitoring` input.
data "aws_iam_policy_document" "agent" {
  statement {
    sid       = "ReadAgentToken"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.agent_token.arn]
  }
}

resource "aws_iam_policy" "agent" {
  name        = "${local.name_prefix}-monitoring-agent"
  description = "Read the PMM agent registration token"
  policy      = data.aws_iam_policy_document.agent.json
}

# Daily snapshots of the data volume (compute.tf).
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
  name               = "${local.name_prefix}-monitoring-dlm"
  assume_role_policy = data.aws_iam_policy_document.dlm_assume.json
}

resource "aws_iam_role_policy_attachment" "dlm" {
  role       = aws_iam_role.dlm.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSDataLifecycleManagerServiceRole"
}

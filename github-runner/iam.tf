# The runners' IAM role. Jobs get AWS credentials from it automatically
# (instance profile), so no AWS keys are ever stored in GitHub.
#
# Base permissions: read the registration token. Everything a job needs on
# top (upload a release, push an image...) is added through var.policy_arns,
# one narrow policy per purpose. Every job on these runners gets all of it.

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "runner" {
  name               = "${local.name_prefix}-github-runner"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_instance_profile" "runner" {
  name = "${local.name_prefix}-github-runner"
  role = aws_iam_role.runner.name
}

data "aws_iam_policy_document" "runner" {
  statement {
    sid       = "ReadRegistrationToken"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.github.arn]
  }
}

resource "aws_iam_role_policy" "runner" {
  name   = "github-runner"
  role   = aws_iam_role.runner.name
  policy = data.aws_iam_policy_document.runner.json
}

resource "aws_iam_role_policy_attachment" "extra" {
  for_each = var.policy_arns

  role       = aws_iam_role.runner.name
  policy_arn = each.value
}

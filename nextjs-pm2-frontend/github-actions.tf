# Lets GitHub Actions in your Next.js repository release (build + upload) on
# every v* tag, without any AWS keys stored in GitHub. GitHub gives each run a
# short-lived OIDC token; AWS trades it for temporary credentials of this role,
# but only for tag runs of that one repository.
#
#   git push origin v1.4.2 ──► GitHub Actions ──OIDC──► this role ──► S3 (releases/, _next/static/)
#
# Deploying to the servers stays a separate, deliberate step (ansible/deploy.yml).
# Created only when github_repository is set.

locals {
  github_enabled = var.github_repository != null
  # Only one GitHub OIDC provider can exist per AWS account: reuse it if given.
  github_oidc_provider_arn = (
    !local.github_enabled ? null :
    var.github_oidc_provider_arn != null ? var.github_oidc_provider_arn :
    aws_iam_openid_connect_provider.github[0].arn
  )
}

resource "aws_iam_openid_connect_provider" "github" {
  count = local.github_enabled && var.github_oidc_provider_arn == null ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "github_assume" {
  count = local.github_enabled ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Only tag pushes (refs/tags/v*) of this repository. Branches, pull
    # requests and forks can't assume the role.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository}:ref:refs/tags/v*"]
    }
  }
}

resource "aws_iam_role" "github_release" {
  count = local.github_enabled ? 1 : 0

  name                 = "${local.name_prefix}-frontend-github-release"
  description          = "GitHub Actions in ${var.github_repository}: release the Next.js frontend on v* tags"
  assume_role_policy   = data.aws_iam_policy_document.github_assume[0].json
  max_session_duration = 3600
}

# Same permissions as the deployer group: upload releases and static files.
resource "aws_iam_role_policy_attachment" "github_release" {
  count = local.github_enabled ? 1 : 0

  role       = aws_iam_role.github_release[0].name
  policy_arn = aws_iam_policy.deployer.arn
}

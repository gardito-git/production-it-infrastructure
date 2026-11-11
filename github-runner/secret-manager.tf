# The GitHub token the runners use ONCE, at first boot, to ask GitHub for a
# registration token. After registering, each runner has its own credentials
# and never needs this token again (until a new runner is added).
#
# Terraform creates the empty secret; YOU put the token in it, so it never
# appears in Terraform code or state:
#
#   aws secretsmanager put-secret-value \
#     --secret-id "$(terraform output -raw github_runner_secret_arn)" \
#     --secret-string '{"token":"github_pat_..."}'
#
# New runners wait at first boot (up to 2 hours) until the token is there.
resource "aws_secretsmanager_secret" "github" {
  # name_prefix adds a random suffix: a deleted secret's name stays reserved for
  # the recovery window, so a fixed name would block destroy + re-create.
  name_prefix             = "${local.name_prefix}/github-runner/"
  description             = "GitHub token for registering self-hosted runners (${var.github_scope}). Set the value by hand."
  recovery_window_in_days = 7
}

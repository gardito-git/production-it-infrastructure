# The web servers' IAM role. It has no permissions of its own; the monitoring
# agents' policy (read the PMM registration token) is attached when enabled.

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "web_server" {
  name               = "${local.name_prefix}-web-server"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_instance_profile" "web_server" {
  name = "${local.name_prefix}-web-server"
  role = aws_iam_role.web_server.name
}

# Monitoring agents may read their PMM registration token (pmm-grafana-dashboard module).
resource "aws_iam_role_policy_attachment" "monitoring" {
  count = var.monitoring == null ? 0 : 1

  role       = aws_iam_role.web_server.name
  policy_arn = var.monitoring.policy_arn
}

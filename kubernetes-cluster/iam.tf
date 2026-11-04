# IAM roles and instance profiles for the cluster nodes: one per node type.
# Their extra permissions are attached where they're used: bootstrap-bucket.tf
# (bootstrap secrets) and backups.tf (etcd snapshots).

# "aws" in commercial regions, "aws-cn" / "aws-us-gov" elsewhere. Using it keeps
# the policy ARNs below valid in every partition.
data "aws_partition" "current" {}

locals {
  # One role per node type, so each can be given only the permissions it needs
  # (e.g. workers must not read the etcd private keys in the bootstrap bucket).
  node_roles = toset(["control-plane", "worker", "etcd"])

  # Shell access is SSH over the VPN (vpc/vpn.tf), so no SSM policy here.
  managed_policies = {
    # Lets containerd pull images from ECR.
    ecr_read = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  }

  # Every role/policy pair, keyed like "worker/ecr_read".
  role_policy_attachments = {
    for pair in setproduct(local.node_roles, keys(local.managed_policies)) :
    "${pair[0]}/${pair[1]}" => { role = pair[0], policy_arn = local.managed_policies[pair[1]] }
  }
}

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# IAM names are global to the AWS account, so include the environment;
# otherwise dev and staging would collide on the same role name.
resource "aws_iam_role" "node" {
  for_each = local.node_roles

  name               = "${var.project_name}-${var.environment}-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = local.role_policy_attachments

  role       = aws_iam_role.node[each.value.role].name
  policy_arn = each.value.policy_arn
}

resource "aws_iam_instance_profile" "node" {
  for_each = local.node_roles

  name = "${var.project_name}-${var.environment}-${each.key}"
  role = aws_iam_role.node[each.key].name
}

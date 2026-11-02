# "aws" in commercial regions, "aws-cn" / "aws-us-gov" elsewhere. Using it keeps
# the policy ARNs below valid in every partition.
data "aws_partition" "current" {}

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
  name               = "${var.project_name}-${var.environment}-node"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

# Lets you open a shell on private nodes through SSM Session Manager, no SSH key needed.
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Lets containerd pull images from ECR.
resource "aws_iam_role_policy_attachment" "ecr_read" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_instance_profile" "node" {
  name = "${var.project_name}-${var.environment}-node"
  role = aws_iam_role.node.name
}

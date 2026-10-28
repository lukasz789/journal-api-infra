# ------------------------------------------------------------------------------
# IAM role used by the EKS control plane (so IAM role for whole EKS cluster)
# ------------------------------------------------------------------------------
# https://docs.aws.amazon.com/eks/latest/userguide/cluster-iam-role.html
data "aws_iam_policy_document" "eks_cluster_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_cluster" {
  name               = "${var.project_name}-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.eks_cluster_assume_role.json

  tags = {
    Name = "${var.project_name}-cluster-role"
  }
}

resource "aws_iam_role_policy_attachment" "eks_cluster" {
  role = aws_iam_role.eks_cluster.name
  # managed policy which allows EKS to manage the cluster
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ------------------------------------------------------------------------------
# IAM role used by EC2 instances in the EKS managed node group
# ------------------------------------------------------------------------------
# https://docs.aws.amazon.com/eks/latest/userguide/create-node-role.html
data "aws_iam_policy_document" "eks_nodes_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_nodes" {
  name               = "${var.project_name}-node-role"
  assume_role_policy = data.aws_iam_policy_document.eks_nodes_assume_role.json

  tags = {
    Name = "${var.project_name}-node-role"
  }
}

resource "aws_iam_role_policy_attachment" "eks_worker_node" {
  role = aws_iam_role.eks_nodes.name
  # managed policy which allows EKS worker nodes to communicate with the control plane
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_ecr_pull" {
  role = aws_iam_role.eks_nodes.name
  # managed policy which allows EKS worker nodes to pull container images from ECR
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"
}

# ------------------------------------------------------------------------------
# IAM role used by the Amazon VPC CNI add-on through EKS Pod Identity
# ------------------------------------------------------------------------------
# https://docs.aws.amazon.com/eks/latest/userguide/add-ons-iam.html
# Trust policy for the VPC CNI IAM role.
# Allows EKS Pod Identity (pods.eks.amazonaws.com) to assume the role
# and provide temporary AWS credentials to the aws-node ServiceAccount.
data "aws_iam_policy_document" "eks_vpc_cni_assume_role" {
  statement {
    effect = "Allow"
    actions = [
      "sts:AssumeRole",
      "sts:TagSession",
    ]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

# IAM role that will be assumed by EKS Pod Identity on behalf of aws-node.
resource "aws_iam_role" "eks_vpc_cni" {
  name               = "${var.project_name}-vpc-cni-role"
  assume_role_policy = data.aws_iam_policy_document.eks_vpc_cni_assume_role.json

  tags = {
    Name = "${var.project_name}-vpc-cni-role"
  }
}

resource "aws_iam_role_policy_attachment" "eks_vpc_cni" {
  role = aws_iam_role.eks_vpc_cni.name
  # managed policy which allows the VPC CNI to manage network interfaces and IP addresses for Pods.
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# ------------------------------------------------------------------------------
# IAM role used by the monitoring Pods through EKS Pod Identity
# ------------------------------------------------------------------------------
# Create one role for the add-on's agents to send logs and traces to AWS.
# This trust policy allows Pod Identity to obtain temporary credentials for it.
# The association in eks-addons.tf selects the Pods that can use the role;
# the policy attached below defines what they are allowed to do in AWS.
data "aws_iam_policy_document" "cloudwatch_agent_assume_role" {
  statement {
    effect = "Allow"
    actions = [
      # Let Pod Identity obtain temporary credentials for this role.
      "sts:AssumeRole",
      # Let Pod Identity label the temporary session with Pod details, such as
      # namespace and ServiceAccount. These session tags can be used to restrict
      # access in IAM policies; we do not add such restrictions here.
      "sts:TagSession",
    ]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cloudwatch_agent" {
  name               = "${var.project_name}-cloudwatch-agent-role"
  assume_role_policy = data.aws_iam_policy_document.cloudwatch_agent_assume_role.json

  tags = {
    Name = "${var.project_name}-cloudwatch-agent-role"
  }
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role = aws_iam_role.cloudwatch_agent.name
  # Give the agents permission to send logs to CloudWatch Logs and traces to X-Ray.
  # This one policy covers both services. It also allows publishing metrics,
  # although our app currently exposes metrics only for Prometheus to collect.
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

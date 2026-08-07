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

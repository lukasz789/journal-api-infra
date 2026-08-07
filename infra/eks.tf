# ------------------------------------------------------------------------------
# EKS control plane
# ------------------------------------------------------------------------------
resource "aws_eks_cluster" "main" {
  name     = var.project_name
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.eks_cluster_version

  vpc_config {
    # EKS creates network interfaces in these subnets to communicate with worker nodes.
    subnet_ids = aws_subnet.private[*].id

    # Communication from inside the VPC can use the private endpoint.
    # -> worker nodes communicate with the control plane through this endpoint.
    endpoint_private_access = true

    # The Kubernetes API is also available through a public endpoint.
    # -> allows managing the cluster outside of AWS network (e.g., from your laptop - with proper IAM credentials).
    endpoint_public_access = true
  }

  # The IAM policy must be attached before EKS starts creating the cluster.
  depends_on = [aws_iam_role_policy_attachment.eks_cluster]

  tags = {
    Name = var.project_name
  }
}

# ------------------------------------------------------------------------------
# EKS managed node group
# ------------------------------------------------------------------------------
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project_name}-nodes"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = aws_subnet.private[*].id

  version        = var.eks_cluster_version
  # Amazon Linux 2023 optimised for EKS
  ami_type       = "AL2023_x86_64_STANDARD"
  capacity_type  = "ON_DEMAND"
  instance_types = [var.eks_node_instance_type]
  # Root EBS volume size in GiB. 20 is default and minimum value for Amazon Linux 2023 AMI.
  disk_size      = 20

  scaling_config {
    min_size     = var.eks_node_min_size
    desired_size = var.eks_node_desired_size
    max_size     = var.eks_node_max_size
  }

  # During an update, EKS replaces no more than one node at a time.
  update_config {
    max_unavailable = 1
  }

  # Nodes are created after their IAM permissions and networking are ready.
  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node,
    aws_iam_role_policy_attachment.eks_ecr_pull,
    aws_eks_addon.vpc_cni,
  ]

  tags = {
    Name = "${var.project_name}-nodes"
  }
}

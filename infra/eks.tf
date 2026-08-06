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

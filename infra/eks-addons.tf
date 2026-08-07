# ------------------------------------------------------------------------------
# EKS Pod Identity Agent
# ------------------------------------------------------------------------------
# The agent provides temporary IAM credentials to Pods which use Pod Identity.
resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name  = aws_eks_cluster.main.name
  addon_name    = "eks-pod-identity-agent"
  addon_version = var.eks_pod_identity_agent_version

  tags = {
    Name = "${var.project_name}-pod-identity-agent"
  }
}

# ------------------------------------------------------------------------------
# Amazon VPC CNI add-on
# ------------------------------------------------------------------------------
# The add-on assigns VPC IP addresses to Pods and manages their network interfaces.
resource "aws_eks_addon" "vpc_cni" {
  cluster_name  = aws_eks_cluster.main.name
  addon_name    = "vpc-cni"
  addon_version = var.eks_vpc_cni_version

  # EKS initially installs a self-managed VPC CNI. This replaces it with an
  # EKS-managed add-on while keeping the configuration controlled by Terraform.
  resolve_conflicts_on_create = "OVERWRITE"

  pod_identity_association {
    service_account = "aws-node"
    role_arn        = aws_iam_role.eks_vpc_cni.arn
  }

  depends_on = [
    aws_eks_addon.pod_identity_agent,
    aws_iam_role_policy_attachment.eks_vpc_cni,
  ]

  tags = {
    Name = "${var.project_name}-vpc-cni"
  }
}

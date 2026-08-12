# ------------------------------------------------------------------------------
# GitHub Actions OIDC provider and IAM role
# ------------------------------------------------------------------------------
# configure GitHub Actions as a trusted identity provider for AWS IAM
resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  tags = {
    Name = "github-actions-oidc"
  }
}

# Only workflows from this repository and the main branch can assume the role.
data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }

    # good practice to keep it, but in this configuration we create identity provider connection above (and it's only for sts.amazonaws.com anyway)
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"

      # Old GitHub OIDC format used only names:
      # values = ["repo:lukasz789/journal-api-infra:ref:refs/heads/main"]
      # New repositories (since 2026) add permanent owner and repository IDs to the same value.
      values   = ["repo:${var.github_repository}:ref:refs/heads/main"]
    }
  }
}

# Role which will be assumed by GitHub Actions workflow.
resource "aws_iam_role" "github_actions" {
  name               = "${var.project_name}-github-actions-role"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role.json

  tags = {
    Name = "${var.project_name}-github-actions-role"
  }
}

# ------------------------------------------------------------------------------
# AWS permissions used by the CI/CD workflow
# ------------------------------------------------------------------------------
data "aws_iam_policy_document" "github_actions" {
  # ECR authorization tokens cannot be restricted to one repository.
  statement {
    sid       = "ECRLogin"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # The workflow can push images only to the Journal API repository.
  statement {
    sid    = "PushJournalApiImage"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [aws_ecr_repository.journal_api.arn]
  }

  # Required by `aws eks update-kubeconfig` in the deploy job.
  # Allows to get information about the EKS cluster, including the API endpoint.
  statement {
    sid       = "DescribeEKSCluster"
    effect    = "Allow"
    actions   = ["eks:DescribeCluster"]
    resources = [aws_eks_cluster.main.arn]
  }

  # The deploy job reads the RDS credentials directly from Secrets Manager.
  statement {
    sid       = "ReadRDSMasterCredentials"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_db_instance.postgresql.master_user_secret[0].secret_arn]
  }
}

resource "aws_iam_role_policy" "github_actions" {
  name   = "${var.project_name}-github-actions-policy"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.github_actions.json
}

# ------------------------------------------------------------------------------
# Kubernetes API access for the GitHub Actions role
# ------------------------------------------------------------------------------
# Accept in the EKS cluster the IAM role used by GitHub Actions workflows.
resource "aws_eks_access_entry" "github_actions" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_iam_role.github_actions.arn
  type          = "STANDARD"

  tags = {
    Name = "${var.project_name}-github-actions-access"
  }
}

# Allow the GitHub Actions role to deploy only to `journal-api` namespace in the EKS cluster.
resource "aws_eks_access_policy_association" "github_actions" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_iam_role.github_actions.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"

  access_scope {
    type       = "namespace"
    namespaces = ["journal-api"]
  }

  depends_on = [aws_eks_access_entry.github_actions]
}

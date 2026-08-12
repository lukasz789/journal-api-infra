#!/usr/bin/env bash

# ----------------------------------------------------------------------------------------------
# Helper script to configure GitHub repository variables with values from Terraform outputs.
# ----------------------------------------------------------------------------------------------

set -e

# Find the repository root so the script works regardless of the current directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

command -v gh >/dev/null 2>&1 || {
    echo "GitHub CLI is not installed."
    exit 1
}

command -v terraform >/dev/null 2>&1 || {
    echo "Terraform is not installed."
    exit 1
}

# Confirm that GitHub CLI is authenticated before changing repository variables.
gh auth status >/dev/null

# Read resource identifiers from the Terraform state created by `terraform apply`.
AWS_ROLE_ARN="$(terraform -chdir="${REPO_ROOT}/infra" output -raw github_actions_role_arn)"
AWS_REGION="$(terraform -chdir="${REPO_ROOT}/infra" output -raw aws_region)"
ECR_REPOSITORY_URL="$(terraform -chdir="${REPO_ROOT}/infra" output -raw ecr_repository_url)"
EKS_CLUSTER_NAME="$(terraform -chdir="${REPO_ROOT}/infra" output -raw eks_cluster_name)"
RDS_HOST="$(terraform -chdir="${REPO_ROOT}/infra" output -raw rds_address)"
RDS_DATABASE_NAME="$(terraform -chdir="${REPO_ROOT}/infra" output -raw rds_database_name)"
RDS_MASTER_USER_SECRET_ARN="$(terraform -chdir="${REPO_ROOT}/infra" output -raw rds_master_user_secret_arn)"

# GitHub CLI detects the target repository from its Git remote.
cd "${REPO_ROOT}"
gh variable set AWS_ROLE_ARN --body "${AWS_ROLE_ARN}"
gh variable set AWS_REGION --body "${AWS_REGION}"
gh variable set ECR_REPOSITORY_URL --body "${ECR_REPOSITORY_URL}"
gh variable set EKS_CLUSTER_NAME --body "${EKS_CLUSTER_NAME}"
gh variable set RDS_HOST --body "${RDS_HOST}"
gh variable set RDS_DATABASE_NAME --body "${RDS_DATABASE_NAME}"
gh variable set RDS_MASTER_USER_SECRET_ARN --body "${RDS_MASTER_USER_SECRET_ARN}"

echo "GitHub Repository Variables configured successfully."

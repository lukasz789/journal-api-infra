#!/usr/bin/env bash
set -e

# Prepare an existing Terraform-managed environment for the first API deployment.
# Run after terraform apply, using an AWS/EKS administrator and authenticated gh.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"
# Disable the AWS CLI pager so bootstrap and helper scripts do not wait for keyboard input.
export AWS_PAGER=""

# ------------------------------------------------------------------------------
# 1. Check tools and access; read the cluster configuration
# ------------------------------------------------------------------------------
echo "==> [1/6] Check prerequisites and access"

for tool in aws terraform kubectl helm gh python; do
    if ! command -v "$tool" >/dev/null; then
        echo "Missing tool: ${tool}. See README.md#1-tools-and-access." >&2
        exit 1
    fi
done

AWS_REGION="$(terraform -chdir="${REPO_ROOT}/infra" output -raw aws_region)"
CLUSTER_NAME="$(terraform -chdir="${REPO_ROOT}/infra" output -raw eks_cluster_name)"

aws sts get-caller-identity
gh repo view --json nameWithOwner --jq '.nameWithOwner'
BEDROCK_SECRET="$(gh secret list --json name \
    --jq '.[] | select(.name == "OPENAI_API_KEY") | .name')"
if [[ -z "$BEDROCK_SECRET" ]]; then
    echo "Set the Bedrock key first: gh secret set OPENAI_API_KEY" >&2
    exit 1
fi

# ------------------------------------------------------------------------------
# 2. Select the Terraform-created cluster and wait for its workers
# ------------------------------------------------------------------------------
echo "==> [2/6] Configure kubectl and wait for workers"

aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"
kubectl wait --for=condition=Ready nodes --all --timeout=5m

# ------------------------------------------------------------------------------
# 3. Create the namespace used by application CI/CD
# ------------------------------------------------------------------------------
echo "==> [3/6] Create the application namespace"
kubectl apply --filename "${REPO_ROOT}/k8s/namespace.yaml"

# ------------------------------------------------------------------------------
# 4. Initialize the private RDS schema through a temporary Kubernetes Job
# ------------------------------------------------------------------------------
echo "==> [4/6] Initialize the database schema"
# pipefail reports a failure anywhere in a pipeline (cmd1 | cmd2), not just in the last command.
bash -o pipefail "${SCRIPT_DIR}/run_database_setup.sh"

# ------------------------------------------------------------------------------
# 5. Refresh GitHub repository variables from Terraform outputs
# ------------------------------------------------------------------------------
echo "==> [5/6] Configure GitHub repository variables"
bash -o pipefail "${SCRIPT_DIR}/configure_github_variables.sh"

# ------------------------------------------------------------------------------
# 6. Install or update monitoring, metric discovery and Grafana dashboards
# ------------------------------------------------------------------------------
echo "==> [6/6] Install or update monitoring"
bash -o pipefail "${SCRIPT_DIR}/install_monitoring.sh"

printf '\nBootstrap complete. Push a new commit to main to deploy the API through GitHub Actions.\n'
printf 'Application metrics appear after CI/CD deploys the API and its metrics Service.\n'

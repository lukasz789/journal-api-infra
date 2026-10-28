#!/usr/bin/env bash
set -e

# Find the script's directory and the project root (one level above it)
# to locate project files regardless of where the script is run.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Pin the chart version so the same code installs the same package version.
CHART_VERSION="92.7.0"

# Check that Helm and kubectl are installed.
command -v helm >/dev/null || { echo "Helm is not installed."; exit 1; }
command -v kubectl >/dev/null || { echo "kubectl is not installed."; exit 1; }

# Use the cluster selected in kubeconfig. Configure EKS access before running this
# script, using an identity allowed to create cluster-wide monitoring resources.
echo "Installing monitoring into Kubernetes context: $(kubectl config current-context)"
kubectl cluster-info >/dev/null

# Register the official chart repository and refresh its list of package versions.
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
helm repo update prometheus-community

# Install or update the monitoring stack using our values.yaml configuration.
# Create the monitoring namespace if needed and wait for Helm-managed resources to be ready.
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
    --version "${CHART_VERSION}" \
    --namespace monitoring \
    --create-namespace \
    --values "${REPO_ROOT}/k8s/monitoring/values.yaml" \
    --wait \
    --timeout 10m

# Wait until the Prometheus Operator has started the Prometheus Pods
# and they are ready to run.
kubectl --namespace monitoring wait \
    --for=condition=Available \
    prometheus/monitoring-kube-prometheus-prometheus \
    --timeout=5m

# Show all monitoring Pods and their status.
kubectl get pods --namespace monitoring

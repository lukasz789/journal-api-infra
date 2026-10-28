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

# ------------------------------------------------------------------------------
# Amazon CloudWatch Observability add-on
# ------------------------------------------------------------------------------
# Install separate Pods to send application monitoring data to AWS:
# - CloudWatch Agent receives traces from Journal API and sends them to X-Ray.
# - Fluent Bit reads container stdout/stderr and sends logs to CloudWatch Logs.
# This one add-on installs both agents and their Kubernetes objects, including
# the Service and ServiceAccount. Their AWS access comes from the role in iam.tf.
# In k8s/deployment.yaml, OTEL_EXPORTER_OTLP_TRACES_ENDPOINT tells Journal API
# where to send its traces: the CloudWatch Agent Service inside EKS.
resource "aws_eks_addon" "cloudwatch_observability" {
  cluster_name  = aws_eks_cluster.main.name
  addon_name    = "amazon-cloudwatch-observability"
  addon_version = var.eks_cloudwatch_observability_version

  configuration_values = jsonencode({
    manager = {
      applicationSignals = {
        # The application already creates traces: api/main.py calls
        # setup_telemetry(app) from api/telemetry.py. Do not let the add-on add
        # another tracing setup to the app, which could trace requests twice.
        autoMonitor = {
          monitorAllServices = false
        }
      }
    }

    agent = {
      # This replaces the agent's default configuration. We omit Kubernetes
      # Container Insights metrics because Prometheus will collect those later.
      config = {
        traces = {
          traces_collected = {
            # Let the agent receive the app's traces over HTTP on port 4316.
            # It then sends them to X-Ray in a separate HTTPS request on port 443,
            # using credentials from Pod Identity. The agent chooses the X-Ray
            # API address for its Region, so we do not set that address here.
            application_signals = {}
          }
        }
      }
    }
  })

  pod_identity_association {
    # Connect the agents' Kubernetes ServiceAccount to the IAM role in iam.tf.
    # Pod Identity gives Pods using this account temporary credentials for that
    # role, so they can write to CloudWatch Logs and X-Ray. The app does not get them.
    service_account = "cloudwatch-agent"
    role_arn        = aws_iam_role.cloudwatch_agent.arn
  }

  # Install after Pod Identity Agent and the role's AWS permissions are ready.
  depends_on = [
    aws_eks_addon.pod_identity_agent,
    aws_iam_role_policy_attachment.cloudwatch_agent,
  ]

  tags = {
    Name = "${var.project_name}-cloudwatch-observability"
  }
}

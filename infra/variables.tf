variable "aws_region" {
  description = "AWS region in which the infrastructure will be created."
  type        = string
}

variable "project_name" {
  description = "Project name used for naming AWS resources."
  type        = string
}

variable "github_repository" {
  description = "GitHub repository allowed to assume the CI/CD IAM role, in owner/name format."
  type        = string
}

variable "eks_cluster_version" {
  description = "Kubernetes minor version used by the EKS control plane."
  type        = string
}

variable "eks_pod_identity_agent_version" {
  description = "Version of the EKS Pod Identity Agent add-on."
  type        = string
}

variable "eks_vpc_cni_version" {
  description = "Version of the Amazon VPC CNI add-on."
  type        = string
}

# AWS Free Tier won't allow you to create a t3.medium instance which is mentioned in terraform.tfvars.example
# If you want to use the AWS Free Tier, you can change the instance type to t3.small
variable "eks_node_instance_type" {
  description = "EC2 instance type used by the EKS managed node group."
  type        = string
}

variable "eks_node_min_size" {
  description = "Minimum number of EC2 instances in the EKS managed node group."
  type        = number
}

variable "eks_node_desired_size" {
  description = "Desired number of EC2 instances in the EKS managed node group."
  type        = number
}

variable "eks_node_max_size" {
  description = "Maximum number of EC2 instances in the EKS managed node group."
  type        = number
}

variable "rds_postgres_version" {
  description = "PostgreSQL version used by the RDS instance."
  type        = string
}

variable "rds_instance_class" {
  description = "Instance class used by the RDS PostgreSQL instance."
  type        = string
}

variable "rds_database_name" {
  description = "Name of the initial PostgreSQL database created by RDS."
  type        = string
}

variable "rds_master_username" {
  description = "Master username for the RDS PostgreSQL instance."
  type        = string
}

variable "vpc_cidr" {
  description = "IPv4 CIDR block assigned to the VPC."
  type        = string
}

variable "public_subnet_cidrs" {
  description = "IPv4 CIDR blocks for the two public subnets."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_cidrs) == 2
    error_message = "public_subnet_cidrs must contain exactly two CIDR blocks."
  }
}

variable "private_subnet_cidrs" {
  description = "IPv4 CIDR blocks for the two private subnets."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_cidrs) == 2
    error_message = "private_subnet_cidrs must contain exactly two CIDR blocks."
  }
}

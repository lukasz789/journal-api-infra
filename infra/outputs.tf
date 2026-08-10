output "aws_region" {
  description = "AWS region selected for this deployment."
  value       = var.aws_region
}

output "ecr_repository_url" {
  description = "URL of the Amazon ECR repository for the Journal API image."
  value       = aws_ecr_repository.journal_api.repository_url
}

output "vpc_id" {
  description = "ID of the VPC used by EKS and RDS."
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets used by internet-facing load balancers."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets used by EKS nodes and RDS."
  value       = aws_subnet.private[*].id
}

output "eks_cluster_name" {
  description = "Name of the EKS cluster."
  value       = aws_eks_cluster.main.name
}

output "eks_cluster_endpoint" {
  description = "Endpoint of the Kubernetes API server."
  value       = aws_eks_cluster.main.endpoint
}

output "rds_address" {
  description = "Private hostname of the RDS PostgreSQL instance."
  value       = aws_db_instance.postgresql.address
}

output "rds_database_name" {
  description = "Name of the initial PostgreSQL database."
  value       = aws_db_instance.postgresql.db_name
}

output "rds_master_user_secret_arn" {
  description = "ARN of the Secrets Manager secret containing the RDS master credentials."
  value       = aws_db_instance.postgresql.master_user_secret[0].secret_arn
}

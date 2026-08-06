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

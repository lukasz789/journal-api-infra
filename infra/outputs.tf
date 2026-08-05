output "aws_region" {
  description = "AWS region selected for this deployment."
  value       = var.aws_region
}

output "ecr_repository_url" {
  description = "URL of the Amazon ECR repository for the Journal API image."
  value       = aws_ecr_repository.journal_api.repository_url
}

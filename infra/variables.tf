variable "aws_region" {
  description = "AWS region in which the infrastructure will be created."
  type        = string
}

variable "project_name" {
  description = "Short project name used as a prefix for AWS resource names."
  type        = string
}

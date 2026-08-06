variable "aws_region" {
  description = "AWS region in which the infrastructure will be created."
  type        = string
}

variable "project_name" {
  description = "Project name used for naming AWS resources."
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

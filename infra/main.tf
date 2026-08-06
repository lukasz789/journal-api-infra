# private repository; for public there is separate resource "aws_ecrpublic_repository"
resource "aws_ecr_repository" "journal_api" {
  name = var.project_name
  # MUTABLE means that the image can be overwritten with the same tag, while IMMUTABLE means that once an image is pushed with a specific tag, it cannot be overwritten.  
  image_tag_mutability = "IMMUTABLE"

  encryption_configuration {
    # options are AES256 or KMS
    encryption_type = "AES256"
  }

  image_scanning_configuration {
    # image known vulnerability scanning
    scan_on_push = true
  }

  tags = {
    Name = "${var.project_name}-ecr"
  }
}

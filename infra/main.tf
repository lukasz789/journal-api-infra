# private repository; for public there is separate resource "aws_ecrpublic_repository"
resource "aws_ecr_repository" "journal_api" {
  name = var.project_name

  # Commit SHA tags cannot be overwritten, but CI/CD can move `latest`
  # to the image built from the newest commit on the main branch.
  image_tag_mutability = "IMMUTABLE_WITH_EXCLUSION"

  image_tag_mutability_exclusion_filter {
    filter      = "latest"
    filter_type = "WILDCARD"
  }

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

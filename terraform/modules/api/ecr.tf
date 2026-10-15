resource "aws_ecr_repository" "api" {
  #checkov:skip=CKV_AWS_136:Images hold code, not customer data; AES-256 encryption at rest (the ECR default) is enough
  name = "${var.name}-api"
  # A tag can never be overwritten, so the commit SHA in a deployment always means the same image.
  image_tag_mutability = "IMMUTABLE"
  # Lets terraform destroy remove the repository with its images at teardown.
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "api" {
  repository = aws_ecr_repository.api.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the 15 most recent images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 15 }
      action       = { type = "expire" }
    }]
  })
}

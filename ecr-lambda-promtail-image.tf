resource "aws_ecr_repository" "ecr_lambda_promtail_image" {
  name                 = "${local.prefix}-lambda-promtail-image"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

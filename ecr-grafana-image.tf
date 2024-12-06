resource "aws_ecr_repository" "ecr_grafana_image" {
  name                 = "${local.prefix}-grafana-image"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

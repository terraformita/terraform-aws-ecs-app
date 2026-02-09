resource "aws_ecr_repository" "container_repository" {
  for_each = local.app_containers_map

  name = "${local.stage_name}/${each.key}"

  force_delete         = var.ecr_force_delete
  image_tag_mutability = each.value.ecr_tag_mutability

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = local.tags
}

resource "aws_ecr_lifecycle_policy" "ecr" {
  for_each = local.app_containers_map

  repository = aws_ecr_repository.container_repository[each.key].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images older than 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Keep only the last ${each.value.ecr_max_images} images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = each.value.ecr_max_images
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

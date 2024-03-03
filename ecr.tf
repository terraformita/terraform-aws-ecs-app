resource "aws_ecr_repository" "container_repository" {
  for_each = local.app_containers_map
  name     = "${local.stage_name}/${each.key}"

  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

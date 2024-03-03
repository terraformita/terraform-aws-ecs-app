locals {
  image_tag = var.image_tag

  container_images = {
    for name, container in local.app_containers_map :
    name => container.image == null ? "${aws_ecr_repository.container_repository[name].repository_url}:${local.image_tag}" : container.image
  }
}

resource "aws_ecs_task_definition" "app" {
  for_each = local.app_containers_map

  family       = "${local.stage_name}-${each.key}"
  network_mode = "awsvpc"

  cpu    = each.value.cpu
  memory = each.value.memory

  requires_compatibilities = ["EC2"] # for fargate will use ["FARGATE"]

  execution_role_arn = aws_iam_role.execution_role.arn
  task_role_arn      = aws_iam_role.task_role[each.key].arn

  container_definitions = jsonencode([
    {
      name  = each.key
      image = local.container_images[each.key]
      portMappings = [
        {
          name          = each.key
          containerPort = each.value.port
        }
      ]
      logConfiguration = {
        logDriver     = "awslogs"
        secretOptions = null
        options = {
          awslogs-group         = "/ecs/${local.stage_name}-${each.key}"
          awslogs-region        = var.region
          awslogs-stream-prefix = "ecs"
        }
      }
      environment = each.value.env_vars == null ? [] : [
        for name, value in each.value.env_vars :
        {
          name  = name
          value = try(local.replacements[each.key][value], value)
        }
      ]
      secrets = each.value.secret_vars == null ? [] : [
        for var, placeholder in each.value.secret_vars :
        {
          name      = var
          valueFrom = try(aws_ssm_parameter.secret["${each.key}_${var}"].arn, aws_ssm_parameter.secret_placeholder["${each.key}_${var}"].arn)
        }
      ]
      mountPoints = each.value.disk_drive.enabled ? [
        {
          sourceVolume  = "efs_volume"
          containerPath = each.value.disk_drive.path
          readOnly      = false
        }
      ] : []
    }
  ])
  dynamic "volume" {
    for_each = each.value.disk_drive.enabled ? [1] : []
    content {
      name = "efs_volume"
      efs_volume_configuration {
        file_system_id     = aws_efs_file_system.efs_file_system.id
        transit_encryption = "ENABLED"

        authorization_config {
          access_point_id = aws_efs_access_point.efs_file_system[each.key].id
        }
      }
    }
  }
}

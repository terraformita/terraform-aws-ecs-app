#### GLOBAL ECS SETTINGS
resource "aws_ecs_account_setting_default" "vpc_trunking" {
  name  = "awsvpcTrunking"
  value = "enabled"
}

#### CONTAINER LOG GROUPS
resource "aws_cloudwatch_log_group" "container" {
  for_each = local.app_containers_map
  name     = "/ecs/${local.stage_name}-${each.key}"
}

################################################################################
# ECS Module
################################################################################
module "ecs_autoscaling" {
  source  = "terraform-aws-modules/ecs/aws"
  version = "4.1.3"

  cluster_name = local.ecs_cluster_name

  cluster_configuration = {
    execute_command_configuration = {
      logging = "OVERRIDE"
      log_configuration = {
        cloud_watch_log_group_name = aws_cloudwatch_log_group.autoscaling.name
      }
    }
  }

  default_capacity_provider_use_fargate = false

  # Capacity provider - Fargate
  fargate_capacity_providers = {
    FARGATE      = {}
    FARGATE_SPOT = {}
  }

  # Capacity provider - autoscaling groups
  autoscaling_capacity_providers = {
    "${local.stage_name}" = {
      auto_scaling_group_arn         = module.autoscaling["ecs"].autoscaling_group_arn
      managed_termination_protection = "ENABLED"

      managed_scaling = {
        maximum_scaling_step_size = 5
        minimum_scaling_step_size = 1
        status                    = "ENABLED"
        target_capacity           = 90
      }

      default_capacity_provider_strategy = {
        weight = 100
      }
    }
  }

  tags = local.tags
}

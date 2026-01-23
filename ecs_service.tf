
resource "aws_ecs_service" "app" {
  for_each        = local.app_containers_map
  name            = "${local.stage_name}-${each.key}"
  cluster         = local.ecs_cluster_id
  task_definition = aws_ecs_task_definition.app[each.key].arn

  dynamic "load_balancer" {
    for_each = each.value.hostname == null ? toset([]) : toset([each.value])
    content {
      target_group_arn = module.ecs_alb[each.value.hostname].target_groups[each.key].arn
      container_name   = each.key
      container_port   = each.value.port
    }
  }

  launch_type   = "EC2" # var.settings.ecs_fargate ? "FARGATE" : "EC2"
  desired_count = each.value.replicas

  deployment_maximum_percent         = each.value.deployment.maximum_percent
  deployment_minimum_healthy_percent = each.value.deployment.minimum_healthy_percent

  network_configuration {
    security_groups = [module.ecs_security_group.security_group_id]
    subnets         = module.vpc.private_subnets
  }

  dynamic "ordered_placement_strategy" {
    for_each = var.deployment_strategy.cost_effective ? toset([1]) : toset([])
    content {
      type  = "binpack"
      field = "memory"
    }
  }

  dynamic "ordered_placement_strategy" {
    for_each = var.deployment_strategy.cost_effective ? toset([1]) : toset([])
    content {
      type  = "binpack"
      field = "cpu"
    }
  }

  deployment_circuit_breaker {
    enable   = var.deployment_strategy.enable_rollback
    rollback = var.deployment_strategy.enable_rollback
  }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.internal.arn
    service {
      client_alias {
        dns_name = each.key
        port     = each.value.port
      }

      port_name = each.key
    }
  }

  tags = merge(var.tags, {
    service     = "${each.key}"
    application = "${local.stage_name}"
  })

  lifecycle {
    ignore_changes = [
      task_definition
    ]
  }
}

resource "aws_appautoscaling_target" "service" {
  for_each           = local.app_containers_map
  max_capacity       = var.autoscaling_instances.max
  min_capacity       = var.autoscaling_instances.min
  resource_id        = "service/${local.ecs_cluster_name}/${aws_ecs_service.app[each.key].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "cpu_threshold" {
  for_each           = local.app_containers_map
  name               = "${local.stage_name}-ecs-scaling-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.service[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.service[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.service[each.key].service_namespace
  target_tracking_scaling_policy_configuration {
    target_value = coalesce(each.value.autoscaling_thresholds.cpu, var.autoscaling_thresholds.cpu)
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

resource "aws_appautoscaling_policy" "memory_threshold" {
  for_each           = local.app_containers_map
  name               = "${local.stage_name}-ecs-scaling-memory"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.service[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.service[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.service[each.key].service_namespace
  target_tracking_scaling_policy_configuration {
    target_value = coalesce(each.value.autoscaling_thresholds.memory, var.autoscaling_thresholds.memory)
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
  }
}

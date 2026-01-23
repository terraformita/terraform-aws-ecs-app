resource "aws_cloudwatch_metric_alarm" "cpu_utilization_high" {
  for_each = local.app_containers_map

  alarm_name          = "${local.stage_name}-cpu-utilization-high-${each.key}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = var.autoscaling_thresholds.cpu

  dimensions = {
    ClusterName = local.ecs_cluster_name
    ServiceName = aws_ecs_service.app[each.key].name
  }

  alarm_description         = "This metric monitors ec2 cpu utilization"
  alarm_actions             = var.alarm_actions
  ok_actions                = var.ok_actions
  insufficient_data_actions = var.alarm_actions

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "memory_utilization_high" {
  for_each = local.app_containers_map

  alarm_name          = "${local.stage_name}-memory-utilization-high-${each.key}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 3
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = var.autoscaling_thresholds.memory

  dimensions = {
    ClusterName = local.ecs_cluster_name
    ServiceName = aws_ecs_service.app[each.key].name
  }

  alarm_description         = "This metric monitors ec2 memory utilization"
  alarm_actions             = var.alarm_actions
  ok_actions                = var.ok_actions
  insufficient_data_actions = var.alarm_actions

  tags = local.tags
}

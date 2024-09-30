locals {
  stage_name = var.stage_name
  host_names = distinct([
    for name, container in local.app_containers_map :
    container.hostname if container.hostname != null
  ])

  ecs_cluster_id   = module.ecs_autoscaling.cluster_id
  ecs_cluster_arn  = module.ecs_autoscaling.cluster_arn
  ecs_cluster_name = "${local.stage_name}-ecs-asg"

  app_containers_map = var.containers

  create_efs = length({
    for name, container in local.app_containers_map :
    name => container if container.disk_drive.enabled
  }) > 0

  host_containers_map = {
    for hostname in local.host_names :
    hostname => [
      for name, container in local.app_containers_map : merge(container, {
        name = name
      })
      if container.hostname == hostname
    ]
  }

  impossible_hostname = "&"
  replacements = {
    for name, container in local.app_containers_map :
    name => {
      "{db_url}"                   = local.db_enabled ? local.db_url : ""
      "{db_name}"                  = local.db_enabled ? local.db_name : ""
      "{db_server}"                = local.db_enabled ? module.db[0].db_instance_address : ""
      "{db_port}"                  = local.db_enabled ? local.db_port : ""
      "{db_user}"                  = local.db_enabled ? local.db_user : ""
      "{db_password}"              = local.db_enabled ? random_password.db_password[0].result : ""
      "{cognito_region}"           = try(var.region, "us-east-1")
      "{cognito_user_pool_arn}"    = try(contains(local.host_based_user_pools, container.hostname), false) ? aws_cognito_user_pool.host_based[container.hostname].arn : (local.create_user_pool ? aws_cognito_user_pool.user_pool[0].arn : "")
      "{cognito_user_pool_id}"     = try(contains(local.host_based_user_pools, container.hostname), false) ? aws_cognito_user_pool.host_based[container.hostname].id : (local.create_user_pool ? aws_cognito_user_pool.user_pool[0].id : "")
      "{cognito_user_pool_domain}" = try(contains(local.host_based_user_pools, container.hostname), false) ? aws_cognito_user_pool.host_based[container.hostname].domain : (local.create_user_pool ? aws_cognito_user_pool.user_pool[0].domain : "")
      "{cognito_client_id}"        = try(aws_cognito_user_pool_client.endpoint_centralized[name].id, try(aws_cognito_user_pool_client.host_based[container.hostname].id, (local.create_user_pool ? aws_cognito_user_pool_client.user_pool[0].id : "")))
      "{cognito_client_secret}"    = try(aws_cognito_user_pool_client.endpoint_centralized[name].client_secret, try(aws_cognito_user_pool_client.host_based[container.hostname].client_secret, (local.create_user_pool ? aws_cognito_user_pool_client.user_pool[0].client_secret : "")))
    }
  }

  tags = merge(var.tags, {
    Application = local.stage_name
  })
}

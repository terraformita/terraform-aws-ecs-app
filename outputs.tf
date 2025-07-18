output "ecs" {
  value = {
    exec_role  = aws_iam_role.execution_role
    task_roles = aws_iam_role.task_role
    services   = aws_ecs_service.app
    asg_name   = module.autoscaling["ecs"].autoscaling_group_name
  }
}

output "ecr" {
  value = {
    repositories = aws_ecr_repository.container_repository
  }
}

output "secrets" {
  value = {
    secret_vars = merge({
      for var in aws_ssm_parameter.secret : var.name => var.arn
      }, {
      for var in aws_ssm_parameter.secret_placeholder : var.name => var.arn
    })
    db_credentials_secret = aws_secretsmanager_secret.db_credentials
  }
}

output "db" {
  value = {
    security_group_ids = local.db_enabled ? [module.rds_sg[0].security_group_id] : null
  }
}

output "vpc" {
  value = {
    vpc_id                     = module.vpc.vpc_id
    database_subnet_group_name = module.vpc.database_subnet_group_name
    public_route_table_ids     = module.vpc.public_route_table_ids
    private_route_table_ids    = module.vpc.private_route_table_ids
    public_subnet_ids          = module.vpc.public_subnets
    private_subnet_ids         = module.vpc.private_subnets
    database_subnet_ids        = module.vpc.database_subnets
    vpc_cidr_block             = module.vpc.vpc_cidr_block
  }
}

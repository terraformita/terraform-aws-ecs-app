output "ecs" {
  value = {
    exec_role  = aws_iam_role.execution_role
    task_roles = aws_iam_role.task_role
    services   = aws_ecs_service.app
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
  }
}

output "vpc" {
  value = {
    vpc_id                  = module.vpc.vpc_id
    db_subnet_group_name    = module.vpc.database_subnet_group
    public_route_table_ids  = module.vpc.public_route_table_ids
    private_route_table_ids = module.vpc.private_route_table_ids
    public_subnet_ids       = module.vpc.public_subnets
    private_subnet_ids      = module.vpc.private_subnets
    vpc_cidr_block          = module.vpc.vpc_cidr_block
  }
}

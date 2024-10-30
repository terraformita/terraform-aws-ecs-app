#### SECRET WITH THE DB PASSWORD
locals {
  db_enabled = var.database == null ? false : true
  db_proto = {
    mysql    = "mysql"
    postgres = "postgres"
  }
  compatible_stage_name   = replace(local.stage_name, "-", "_")
  server_name             = try(var.database.server_name, null) == null ? local.compatible_stage_name : var.database.server_name
  db_name                 = try(var.database.db_name, null) == null ? local.stage_name : var.database.db_name
  db_port                 = try(var.database.port, null) == null ? 3306 : var.database.port
  db_user                 = try(var.database.user, null) == null ? "root" : var.database.user
  db_engine               = try(var.database.engine, null) == null ? "mysql" : var.database.engine
  db_engine_version       = try(var.database.engine_version, null) == null ? "8.0" : var.database.engine_version
  db_major_engine_version = try(var.database.major_engine_version, null) == null ? local.db_engine_version : var.database.major_engine_version
  db_log_exports          = try(var.database.log_exports, null) == null ? ["general"] : var.database.log_exports
  db_storage_gb           = try(var.database.storage_gb, null) == null ? 20 : var.database.storage_gb
  db_multi_az             = try(var.database.multi_az, null) == null ? false : var.database.multi_az
  db_instance_type        = try(var.database.instance_type, null) == null ? "db.t3.micro" : var.database.instance_type
  db_parameters_family    = try(var.database.parameters_family, null) == null ? null : var.database.parameters_family
  db_enforce_ssl          = try(var.database.enforce_ssl, true)
  db_parameters = try(var.database.db_parameters, null) == null ? [] : [
    for name, value in var.database.db_parameters : {
      name  = name
      value = value
    }
  ]
}

resource "random_password" "db_password" {
  count  = local.db_enabled ? 1 : 0
  length = 16

  lower   = true
  upper   = true
  special = false

  override_special = "$-_.+!*'()"

  min_special = 2
  min_upper   = 2
  min_lower   = 2
  min_numeric = 2

  keepers = {
    locked = true
  }
}

module "rds_sg" {
  count   = local.db_enabled ? 1 : 0
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 4.0"

  name        = "${local.stage_name}-db"
  description = "${local.stage_name} database"
  vpc_id      = module.vpc.vpc_id

  # MySQL port ingress from inside the VPC
  ingress_with_cidr_blocks = [{
    from_port   = local.db_port
    to_port     = local.db_port
    protocol    = "tcp"
    description = "Database access from within VPC"
    cidr_blocks = module.vpc.vpc_cidr_block
  }]

  egress_cidr_blocks = [module.vpc.vpc_cidr_block]
  egress_rules       = ["all-all"]

  tags = local.tags
}

module "db" {
  count   = local.db_enabled ? 1 : 0
  source  = "terraform-aws-modules/rds/aws"
  version = "5.4.2"

  identifier = local.stage_name

  # All available versions: http://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_MySQL.html#MySQL.Concepts.VersionMgmt
  engine               = local.db_engine
  engine_version       = local.db_engine_version
  family               = local.db_parameters_family    # "${local.db_engine}${local.db_engine_version}" # DB parameter group
  major_engine_version = local.db_major_engine_version # DB option group
  instance_class       = local.db_instance_type

  create_db_parameter_group = local.db_parameters_family != null

  allocated_storage     = local.db_storage_gb
  max_allocated_storage = local.db_storage_gb * 5

  db_name  = local.db_name
  username = local.db_user
  password = random_password.db_password[0].result
  port     = local.db_port

  multi_az               = var.database.multi_az
  db_subnet_group_name   = module.vpc.database_subnet_group
  vpc_security_group_ids = [module.rds_sg[0].security_group_id]

  maintenance_window              = "Mon:00:00-Mon:03:00"
  backup_window                   = "03:00-06:00"
  enabled_cloudwatch_logs_exports = local.db_log_exports
  create_cloudwatch_log_group     = true
  blue_green_update = {
    enabled = false
  }

  skip_final_snapshot = true
  deletion_protection = true

  performance_insights_enabled          = false
  performance_insights_retention_period = 7
  create_monitoring_role                = true
  monitoring_role_name                  = "${local.stage_name}-rds-monitoring-role"
  monitoring_interval                   = 60
  create_random_password                = false

  parameters = local.db_parameters

  tags = local.tags

  db_instance_tags        = local.tags
  db_option_group_tags    = local.tags
  db_parameter_group_tags = local.tags
  db_subnet_group_tags    = local.tags
}

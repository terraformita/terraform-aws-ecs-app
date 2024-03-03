locals {
  db_sslmode    = local.db_enforce_ssl ? "?sslmode=require" : ""
  db_url        = local.db_enabled ? "${local.db_proto[local.db_engine]}://${local.db_user}:${random_password.db_password[0].result}@${module.db[0].db_instance_address}/${local.db_name}${local.db_sslmode}" : ""
  secret_params = merge([for secrets_map in local.container_secrets : secrets_map]...)

  container_secrets = {
    for name, container in local.app_containers_map :
    name => {
      for secret, placeholder in container.secret_vars :
      "${name}_${secret}" => {
        secret_name = secret
        container   = name
        placeholder = placeholder == "" ? "empty" : placeholder
      }
    }
  }
}

resource "aws_secretsmanager_secret" "app_vars" {
  name = "${local.stage_name}-secrets"
}

resource "aws_secretsmanager_secret_version" "app_vars" {
  secret_id     = aws_secretsmanager_secret.app_vars.id
  secret_string = jsonencode({})

  lifecycle {
    ignore_changes = [
      secret_string
    ]
  }
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name = "${local.stage_name}-db-secrets"
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  count     = local.db_enabled ? 1 : 0
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    "DB_NAME"     = local.db_name
    "DB_PASSWORD" = random_password.db_password[0].result
    "DB_USER"     = local.db_user
    "DB_HOST"     = module.db[0].db_instance_address
    "DB_PORT"     = local.db_port
    "DB_URL"      = local.db_url
  })
}

resource "aws_ssm_parameter" "secret" {
  for_each = {
    for secret, value in local.secret_params :
    secret => value if contains(keys(local.replacements[value.container]), value.placeholder)
  }
  name        = "/${local.stage_name}/${each.value.container}/${each.value.secret_name}"
  description = "Secret parameter for container ${each.value.container}"
  type        = "SecureString"
  value       = try(local.replacements[each.value.container][each.value.placeholder], "empty")

  tags = local.tags
}

resource "aws_ssm_parameter" "secret_placeholder" {
  for_each = {
    for secret, value in local.secret_params :
    secret => value if !contains(keys(local.replacements[value.container]), value.placeholder)
  }
  name        = "/${local.stage_name}/${each.value.container}/${each.value.secret_name}"
  description = "Secret (placeholder) parameter for container ${each.value.container}"
  type        = "SecureString"
  value       = "empty"

  tags = local.tags

  lifecycle {
    ignore_changes = [
      value
    ]
  }
}

locals {
  # Add SSL mode to DB URL if required
  # Example: "?sslmode=require"
  db_sslmode = local.db_enforce_ssl ? "?sslmode=require" : ""

  # Build full DB connection URL
  # Example:
  #   "postgresql://user:pass@host/dbname?sslmode=require"
  db_url = local.db_enabled ? format(
    "%s://%s:%s@%s/%s%s",
    local.db_proto[local.db_engine],       # Example: "postgresql"
    local.db_user,                         # Example: "appuser"
    random_password.db_password[0].result, # Example: "p@ssw0rd"
    module.db[0].db_instance_address,      # Example: "db.cluster.amazonaws.com"
    local.db_name,                         # Example: "mydb"
    local.db_sslmode
  ) : ""

  # Build per-container secret map structure
  # Input: local.app_containers_map = {
  #   api = {
  #     secret_vars = {
  #       DB_USER = "DB_USER_PLACEHOLDER"
  #     }
  #   }
  # }
  #
  # Output: {
  #   "api_DB_USER" = {
  #     secret_name = "DB_USER"
  #     container   = "api"
  #     placeholder = "DB_USER_PLACEHOLDER"
  #   }
  # }
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

  # Flatten all per-container secret maps into one flat map
  secret_params = merge([
    for secrets_map in local.container_secrets : secrets_map
  ]...)

  # Secrets with a real value present in local.replacements
  resolved_secrets = {
    for secret, value in local.secret_params :
    secret => value if contains(keys(local.replacements[value.container]), value.placeholder)
  }

  # Secrets with no replacement provided — fallback to "empty"
  unresolved_secrets = {
    for secret, value in local.secret_params :
    secret => value if !contains(keys(local.replacements[value.container]), value.placeholder)
  }

  # DB secret JSON payload for Secrets Manager
  db_secret_payload = {
    DB_NAME     = local.db_name
    DB_PASSWORD = random_password.db_password[0].result
    DB_USER     = local.db_user
    DB_HOST     = module.db[0].db_instance_address
    DB_PORT     = local.db_port
    DB_URL      = local.db_url
  }
}

# ----------------------
# Secrets Manager: App-Level Empty Secret
# ----------------------

resource "aws_secretsmanager_secret" "app_vars" {
  name = "${local.stage_name}-secrets"
}

resource "aws_secretsmanager_secret_version" "app_vars" {
  secret_id     = aws_secretsmanager_secret.app_vars.id
  secret_string = jsonencode({})

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# ----------------------
# Secrets Manager: DB Credentials
# ----------------------

resource "aws_secretsmanager_secret" "db_credentials" {
  name = "${local.stage_name}-db-secrets"
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  count         = local.db_enabled ? 1 : 0
  secret_id     = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode(local.db_secret_payload)
}

# ----------------------
# SSM Parameters: Actual Values
# ----------------------

resource "aws_ssm_parameter" "secret" {
  for_each = local.resolved_secrets

  name        = "/${local.stage_name}/${each.value.container}/${each.value.secret_name}"
  description = "Secret parameter for container ${each.value.container}"
  type        = "SecureString"

  value = coalesce(
    try(local.replacements[each.value.container][each.value.placeholder], ""),
    "empty"
  )

  tags = local.tags
}

# ----------------------
# SSM Parameters: Placeholders
# ----------------------

resource "aws_ssm_parameter" "secret_placeholder" {
  for_each = local.unresolved_secrets

  name        = "/${local.stage_name}/${each.value.container}/${each.value.secret_name}"
  description = "Secret (placeholder) parameter for container ${each.value.container}"
  type        = "SecureString"
  value       = "empty"
  tags        = local.tags

  lifecycle {
    ignore_changes = [value]
  }
}

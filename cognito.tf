locals {
  auth_enabled_hosts = {
    for hostname, config in var.host_based_auth :
    hostname => merge(config, {
      callback_url = "https://${hostname}.${var.domain_name}${config.callback_path}"
    })
  }

  host_based_user_pools = [
    for hostname, config in var.host_based_auth :
    hostname if config.separate_user_pool == true
  ]

  auth_enabled_endpoints = {
    for container, config in local.app_containers_map :
    container => merge(config, {
      callback_url = "https://${config.hostname}.${var.domain_name}${config.user_auth.callback_path}"
    }) if config.user_auth != null
  }

  auth_identity_providers = var.identity_providers

  automated_auth_hosts = {
    for hostname, config in local.auth_enabled_hosts :
    hostname => config if config.automated == true
  }

  # Create centralized user pool if any of the hosts are not using their own
  create_user_pool = length(local.host_based_user_pools) != length(local.host_names)

  cognito_domain = local.stage_name # "auth-${local.stage_name}.${var.domain_name}"
  # "https://${aws_cognito_user_pool.user_pool[0].id}.auth.${var.region}.amazoncognito.com/oauth2/idpresponse" : ""
  default_callback_path = "/oauth2/idpresponse"
  cognito_callback_urls = concat(
    local.create_user_pool ? [
      "https://${aws_cognito_user_pool.user_pool[0].id}.auth.${var.region}.amazoncognito.com${local.default_callback_path}"
      ] : [], [
      for hostname in local.host_names : "https://${hostname}.${var.domain_name}${local.default_callback_path}"
    ]
  )

  cognito_sms_external_id = random_uuid.external_id.result
}

resource "random_uuid" "external_id" {
}

resource "random_id" "id" {
  byte_length = 8
}

#### COGNITO USER POOL
resource "aws_cognito_user_pool" "user_pool" {
  count             = local.create_user_pool ? 1 : 0
  name              = "${local.stage_name}-user-pool"
  mfa_configuration = "OPTIONAL"

  auto_verified_attributes = [
    "email",
    "phone_number"
  ]

  # Allow user sign-ups
  admin_create_user_config {
    allow_admin_create_user_only = !var.auth.allow_user_sign_up
  }

  username_attributes = ["email"]

  username_configuration {
    case_sensitive = false
  }

  password_policy {
    minimum_length                   = 10
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    require_uppercase                = true
    temporary_password_validity_days = 7
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }

    recovery_mechanism {
      name     = "verified_phone_number"
      priority = 2
    }
  }

  software_token_mfa_configuration {
    enabled = true
  }

  user_attribute_update_settings {
    attributes_require_verification_before_update = [
      "email",
      "phone_number"
    ]
  }

  lambda_config {
    pre_sign_up = module.pre_signup_lambda.lambda_function.arn
  }

  sms_configuration {
    external_id    = local.cognito_sms_external_id
    sns_caller_arn = aws_iam_role.user_pool.arn
  }

  dynamic "email_configuration" {
    for_each = toset(aws_ses_email_identity.sender_email[*])
    content {
      email_sending_account = "DEVELOPER"
      from_email_address    = email_configuration.value.email
      source_arn            = email_configuration.value.arn
    }
  }

  #   sms_authentication_message = var.messages.sms_authentication_message
  #   # tflint-ignore: aws_cognito_user_pool_invalid_sms_verification_message
  #   sms_verification_message   = var.messages.sms_verification_message
  #   email_verification_subject = var.messages.email_verification_subject
  #   email_verification_message = var.messages.email_verification_message

  tags = local.tags
}

resource "aws_cognito_user_pool" "host_based" {
  for_each          = toset(local.host_based_user_pools)
  name              = "${local.stage_name}-${each.value}"
  mfa_configuration = "OPTIONAL"

  auto_verified_attributes = [
    "email",
    "phone_number"
  ]

  admin_create_user_config {
    allow_admin_create_user_only = !local.auth_enabled_hosts[each.value].allow_user_sign_up
  }

  username_attributes = ["email"]

  username_configuration {
    case_sensitive = false
  }

  password_policy {
    minimum_length                   = 10
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    require_uppercase                = true
    temporary_password_validity_days = 7
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }

    recovery_mechanism {
      name     = "verified_phone_number"
      priority = 2
    }
  }

  software_token_mfa_configuration {
    enabled = true
  }

  user_attribute_update_settings {
    attributes_require_verification_before_update = [
      "email",
      "phone_number"
    ]
  }

  lambda_config {
    pre_sign_up = module.pre_signup_lambda.lambda_function.arn
  }

  sms_configuration {
    external_id    = local.cognito_sms_external_id
    sns_caller_arn = aws_iam_role.user_pool.arn
  }

  dynamic "email_configuration" {
    for_each = toset(aws_ses_email_identity.sender_email[*])
    content {
      email_sending_account = "DEVELOPER"
      from_email_address    = email_configuration.value.email
      source_arn            = email_configuration.value.arn
    }
  }

  #   sms_authentication_message = var.messages.sms_authentication_message
  #   # tflint-ignore: aws_cognito_user_pool_invalid_sms_verification_message
  #   sms_verification_message   = var.messages.sms_verification_message
  #   email_verification_subject = var.messages.email_verification_subject
  #   email_verification_message = var.messages.email_verification_message

  tags = local.tags
}

# TODO: return this back when possible
resource "aws_cognito_user_pool_domain" "user_pool" {
  count        = local.create_user_pool ? 1 : 0
  domain       = local.stage_name
  user_pool_id = aws_cognito_user_pool.user_pool[0].id
}

resource "aws_cognito_user_pool_domain" "host_based" {
  for_each     = toset(local.host_based_user_pools)
  domain       = "${local.stage_name}-${each.value}"
  user_pool_id = aws_cognito_user_pool.host_based[each.key].id
}

#### COGNITO IDENTITY PROVIDERS
resource "aws_cognito_identity_provider" "user_pool_idp" {
  for_each      = local.create_user_pool ? local.auth_identity_providers : {}
  user_pool_id  = aws_cognito_user_pool.user_pool[0].id
  provider_name = each.key
  provider_type = each.value.type

  provider_details = {
    MetadataURL = each.value.metadata_url
  }

  attribute_mapping = each.value.attribute_mapping

  depends_on = [
    aws_cognito_user_pool.user_pool
  ]
}

resource "aws_cognito_identity_provider" "host_based_idp" {
  for_each = merge(flatten([
    for user_pool in aws_cognito_user_pool.host_based : {
      for provider, config in local.auth_identity_providers :
      "${user_pool.id}_${provider}" => merge(config, {
        provider_name = provider
        user_pool_id  = user_pool.id
      })
    }
  ])...)

  user_pool_id  = each.value.user_pool_id
  provider_name = each.value.provider_name
  provider_type = each.value.type

  provider_details = {
    MetadataURL = each.value.metadata_url
  }

  attribute_mapping = each.value.attribute_mapping

  depends_on = [
    aws_cognito_user_pool.host_based
  ]
}

# COGNITO USER POOL CLIENTS
resource "aws_cognito_user_pool_client" "user_pool" {
  count = local.create_user_pool ? 1 : 0
  name  = "${local.stage_name}-user-pool-client"

  user_pool_id    = aws_cognito_user_pool.user_pool[0].id
  generate_secret = true

  explicit_auth_flows = [
    "ALLOW_CUSTOM_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_USER_SRP_AUTH"
  ]

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "minutes"
  }

  refresh_token_validity = var.auth.refresh_token_validity
  access_token_validity  = var.auth.access_token_validity
  id_token_validity      = var.auth.id_token_validity

  allowed_oauth_scopes = [
    "phone",
    "email",
    "openid",
    "profile"
  ]

  allowed_oauth_flows_user_pool_client = true

  allowed_oauth_flows = ["code"]
  logout_urls = [
    for hostname in local.host_names :
    "https://${hostname}.${var.domain_name}"
  ]
  callback_urls        = local.cognito_callback_urls
  default_redirect_uri = local.cognito_callback_urls[0]

  enable_token_revocation       = true
  prevent_user_existence_errors = "ENABLED"
  supported_identity_providers = concat(
    keys(local.auth_identity_providers),
    ["COGNITO"]
  )

  depends_on = [
    aws_cognito_identity_provider.user_pool_idp
  ]
}

resource "aws_cognito_user_pool_client" "endpoint_centralized" {
  for_each = local.create_user_pool ? {
    for container, config in local.auth_enabled_endpoints :
    container => config if !contains(local.host_based_user_pools, config.hostname)
  } : {}
  name = "${var.stage_name}-${each.key}"

  user_pool_id    = aws_cognito_user_pool.user_pool[0].id
  generate_secret = true

  explicit_auth_flows = [
    "ALLOW_CUSTOM_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_USER_SRP_AUTH"
  ]

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "minutes"
  }

  refresh_token_validity = each.value.user_auth.refresh_token_validity
  access_token_validity  = each.value.user_auth.access_token_validity
  id_token_validity      = each.value.user_auth.id_token_validity

  allowed_oauth_scopes = [
    "phone",
    "email",
    "openid",
    "profile"
  ]

  allowed_oauth_flows_user_pool_client = true

  allowed_oauth_flows = ["code"]
  logout_urls = [
    "https://${each.value.hostname}${var.domain_name}"
  ]
  callback_urls        = [each.value.callback_url]
  default_redirect_uri = each.value.callback_url

  enable_token_revocation       = true
  prevent_user_existence_errors = "ENABLED"
  supported_identity_providers = concat(
    each.value.user_auth.identity_providers,
    ["COGNITO"]
  )

  depends_on = [
    aws_cognito_identity_provider.user_pool_idp
  ]
}

resource "aws_cognito_user_pool_client" "host_based" {
  for_each = {
    for hostname, config in local.auth_enabled_hosts :
    hostname => config if contains(local.host_based_user_pools, hostname)
  }
  name = "${var.stage_name}-${each.key}"

  user_pool_id    = aws_cognito_user_pool.host_based[each.key].id
  generate_secret = true

  explicit_auth_flows = [
    "ALLOW_CUSTOM_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_USER_SRP_AUTH"
  ]

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "minutes"
  }

  refresh_token_validity = each.value.refresh_token_validity
  access_token_validity  = each.value.access_token_validity
  id_token_validity      = each.value.id_token_validity

  allowed_oauth_scopes = [
    "phone",
    "email",
    "openid",
    "profile"
  ]

  allowed_oauth_flows_user_pool_client = true

  allowed_oauth_flows = ["code"]
  logout_urls = [
    "https://${each.key}.${var.domain_name}"
  ]
  callback_urls        = [each.value.callback_url]
  default_redirect_uri = each.value.callback_url

  enable_token_revocation       = true
  prevent_user_existence_errors = "ENABLED"
  supported_identity_providers = concat(
    each.value.identity_providers,
    ["COGNITO"]
  )

  depends_on = [
    aws_cognito_identity_provider.host_based_idp
  ]
}

## AUTH LAMBDA
data "archive_file" "auth_lambda" {
  type = "zip"

  source_dir  = "${path.module}/lambda/userinfo/code"
  output_path = "${path.module}/lambda/userinfo/lambda_handler.py.zip"
}

module "auth_lambda" {
  for_each = local.auth_enabled_hosts
  source   = "terraformita/lambda/aws"
  version  = "0.2.3"

  stage = "${local.stage_name}-${each.key}"
  tags  = local.tags

  function = {
    name        = "userinfo"
    description = "Userinfo endpoint for '${each.key}' host."

    zip     = "${path.module}/lambda/userinfo/lambda_handler.py.zip"
    handler = "lambda_handler.lambda_handler"
    runtime = "python3.8"
    memsize = "256"

    track_versions = true

    env = {
      BASE_URI             = "https://${each.key}.${var.domain_name}"
      CLIENT_ID            = try(aws_cognito_user_pool_client.host_based[each.key].id, (local.create_user_pool ? aws_cognito_user_pool_client.user_pool[0].id : ""))
      CLIENT_SECRET        = sensitive(try(aws_cognito_user_pool_client.host_based[each.key].client_secret, (local.create_user_pool ? aws_cognito_user_pool_client.user_pool[0].client_secret : "")))
      COGNITO_DOMAIN       = try(aws_cognito_user_pool_domain.host_based[each.key].domain, local.create_user_pool ? aws_cognito_user_pool_domain.user_pool[0].domain : "")
      COGNITO_USER_POOL_ID = try(aws_cognito_user_pool.host_based[each.key].id, (local.create_user_pool ? aws_cognito_user_pool.user_pool[0].id : ""))
      LOG_LEVEL            = "INFO"
      REDIRECT_URI         = each.value.callback_url
      REGION               = var.region
      RETURN_URI           = "https://${each.key}.${var.domain_name}"
    }
  }

  logs = {
    log_retention_days = var.log_retention_days
    kms_key_arn        = var.kms_key_arn
  }

  layer = {
    zip                 = "${path.module}/lambda/userinfo/sdk-layer.zip"
    compatible_runtimes = ["python3.8"]
  }

  depends_on = [
    data.archive_file.auth_lambda
  ]
}

#### PRE-SIGNUP LAMBDA
data "archive_file" "pre_signup_lambda" {
  type = "zip"

  source_file = "${path.module}/lambda/pre-signup/index.js"
  output_path = "${path.module}/lambda/pre-signup/pre_signup.js.zip"
}

module "pre_signup_lambda" {
  source  = "terraformita/lambda/aws"
  version = "0.2.3"

  stage = local.stage_name
  tags  = local.tags

  function = {
    name        = "cognito-pre-signup"
    description = "Pre-signup lambda for ${local.stage_name} app, that performs automatic verification of user's email and phone number."

    zip     = "${path.module}/lambda/pre-signup/pre_signup.js.zip"
    handler = "index.handler"
    runtime = "nodejs16.x"
    memsize = 128

    reserved_concurrency = var.cognito_pre_signup_reserved_concurrency
  }

  logs = {
    log_retention_days = var.log_retention_days
    kms_key_arn        = var.kms_key_arn
  }

  depends_on = [
    data.archive_file.pre_signup_lambda
  ]
}

resource "aws_lambda_permission" "user_pool" {
  count         = local.create_user_pool ? 1 : 0
  action        = "lambda:InvokeFunction"
  function_name = module.pre_signup_lambda.lambda_function.function_name
  principal     = "cognito-idp.amazonaws.com"
  source_arn    = aws_cognito_user_pool.user_pool[0].arn
}

resource "aws_lambda_permission" "host_based" {
  for_each      = toset(local.host_based_user_pools)
  action        = "lambda:InvokeFunction"
  function_name = module.pre_signup_lambda.lambda_function.function_name
  principal     = "cognito-idp.amazonaws.com"
  source_arn    = aws_cognito_user_pool.host_based[each.key].arn
}

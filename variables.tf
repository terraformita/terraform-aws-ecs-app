variable "stage_name" {
  description = "Stage name of the current set up (e.g. 'myproduct-dev' or 'myproduct-prod')"
  type        = string
}

variable "vpc" {
  description = "Object containing all VPC information to create"
  type = object({
    vpc_id                  = optional(string)
    db_subnet_group_name    = optional(string)
    public_route_table_ids  = optional(list(string))
    private_route_table_ids = optional(list(string))
    public_subnet_ids       = optional(list(string))
    private_subnet_ids      = optional(list(string))

    vpc_cidr_block   = string
    azs              = optional(list(string))
    public_subnets   = optional(list(string))
    private_subnets  = optional(list(string))
    database_subnets = optional(list(string))
  })
}

variable "tags" {
  description = "Tags to apply to all AWS resources created"
  type        = map(string)
}

variable "autoscaling_instances" {
  description = "Number of instances to launch in the autoscaling group"
  type = object({
    min                 = number
    max                 = number
    desired             = number
    instance_type       = string
    use_spot_instances  = optional(bool, false)
    spot_instance_price = optional(string, "0.01")
  })
}

variable "autoscaling_thresholds" {
  description = "Values for scaling thresholds"
  type = object({
    cpu    = number
    memory = number
  })

  default = {
    cpu    = 80
    memory = 90
  }
}

variable "auth" {
  description = "Centralized user authentication configuration"
  type = object({
    allow_user_sign_up     = optional(bool, true)
    identity_providers     = optional(list(string), [])
    callback_path          = optional(string, "/oauth2/idpresponse")
    refresh_token_validity = optional(number, 1440)
    access_token_validity  = optional(number, 60)
    id_token_validity      = optional(number, 60)
  })
  default = {}
}

variable "host_based_auth" {
  description = "Host-based user authentication configuration"
  type = map(object({
    user_pool_id = optional(string, "centralized")
    automated    = optional(bool, true)

    service_endpoints = optional(object({
      userinfo = optional(string, "/oauth2/userinfo")
      logout   = optional(string, "/oauth2/logout")
    }), {})

    allow_user_sign_up = optional(bool, true)

    identity_providers = optional(list(string), [])

    callback_path = optional(string, "/oauth2/idpresponse")

    refresh_token_validity = optional(number, 1440)
    access_token_validity  = optional(number, 60)
    id_token_validity      = optional(number, 60)

    separate_user_pool = optional(bool, false)
  }))
  default = {}
}

variable "containers" {
  description = "List of containers to run in the ECS task"
  type = map(object({
    hostname       = optional(string)
    web_path       = optional(string, "/")
    web_entrypoint = optional(bool, false)
    protocol       = string
    image          = optional(string)
    port           = number
    cpu            = number
    memory         = number
    replicas       = optional(number, 1)

    deployment = optional(object({
      maximum_percent         = optional(number, 200)
      minimum_healthy_percent = optional(number, 100)
    }), {})

    env_vars    = optional(map(string))
    env_files   = optional(map(string))
    secret_vars = optional(map(string), {})
    disk_drive = optional(object({
      enabled = optional(bool, false)
      size_gb = optional(number, 10)
      path    = optional(string, "/mnt/data")
      uid     = optional(number, 2001)
      gid     = optional(number, 2001)
    }), {})

    health_check = optional(object({
      interval       = number
      timeout        = number
      path           = string
      response_codes = string
    }))

    accessible_cloud_storage = optional(list(string), [])

    user_auth = optional(object({
      automated = optional(bool, true)

      identity_providers = optional(list(string), [])
      callback_path      = optional(string, "/oauth2/idpresponse")

      refresh_token_validity = optional(number, 1440)
      access_token_validity  = optional(number, 60)
      id_token_validity      = optional(number, 60)
    }))
  }))
}

variable "region" {
  description = "AWS region to deploy to"
  type        = string
}

variable "domain_name" {
  description = "Domain name of the application"
  type        = string
}

variable "zone_id" {
  description = "ID of the Route53 zone where records will be created."
  type        = string
  default     = ""
}

variable "manage_dns" {
  description = "Whether to manage Route53 DNS records."
  type        = bool
  default     = false
}

variable "deployment_strategy" {
  description = "Deployment strategy settings"
  type = object({
    enable_rollback = optional(bool, false)
    cost_effective  = optional(bool, true)
  })
}

variable "ssl_certificate" {
  description = "SSL certificate parameters"
  type = object({
    key_algorithm = string
    key_length    = number
    organization  = string
    self_signed   = optional(bool, false)
  })

  default = {
    key_algorithm = "RSA"
    key_length    = 2048
    organization  = "ACME Corporation"
  }
}

variable "access_logs_bucket_id" {
  description = "ID of the S3 bucket to store access logs"
  type        = string
}

variable "database" {
  description = "Configuration of the main application database"
  type = object({
    db_name               = optional(string)
    port                  = optional(number)
    user                  = optional(string)
    engine                = optional(string)
    engine_version        = optional(string)
    major_engine_version  = optional(string)
    family                = optional(string, null)
    db_parameters         = optional(map(string))
    instance_type         = optional(string)
    storage_gb            = optional(number)
    multi_az              = optional(bool)
    log_exports           = optional(list(string))
    enforce_ssl           = optional(bool, true)
    iam_auth              = optional(bool, false)
    copy_tags_to_snapshot = optional(bool, false)
    apply_immediately     = optional(bool, false)
  })

  default  = null
  nullable = true
}

variable "mail_sending" {
  description = "Value for the 'From' field in emails sent by the application"
  type = object({
    enabled      = bool
    from_address = optional(string)
  })

  default = {
    enabled = false
  }
}

variable "image_tag" {
  description = "Tag of the Docker image to deploy"
  type        = string
  default     = "latest"
}

variable "identity_providers" {
  description = "List of identity providers to configure for user authentication"
  type = map(object({
    type              = string
    metadata_url      = string
    attribute_mapping = map(string)
  }))
  default = {}
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs."
  type        = number
  nullable    = false
  default     = 7
}

variable "kms_key_arn" {
  description = "KMS key used to CloudWatch log data encryption."
  type        = string
  default     = null
}

variable "autoscaling_group_tags" {
  description = "A map of additional tags to add to the autoscaling group."
  type        = map(string)
  default     = {}
}

variable "lt_tag_specifications" {
  description = "The tags to apply to the launch template resources during launch."
  type        = list(any)
  default     = []
}

variable "cognito_lambda_reserved_concurrency" {
  description = "Reserved concurrency for the cognito pre-signup lambda."
  type        = number
  default     = -1
}

variable "lambda_shared_dlq" {
  description = "ARN of the Dead Letter Queue (SQS or SNS) for lambdas."
  type        = string
  default     = null
}

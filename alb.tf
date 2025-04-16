locals {
  # Build list of web paths, and sort them by longest path first
  web_paths = {
    for hostname in local.host_names : hostname =>
    reverse(
      concat(
        sort([for container in local.host_containers_map[hostname] : container.web_path]),
        contains(keys(local.auth_enabled_hosts), hostname) && try(local.auth_enabled_hosts[hostname].automated, false) ? [
          local.auth_enabled_hosts[hostname].service_endpoints.userinfo,
          local.auth_enabled_hosts[hostname].service_endpoints.logout
        ] : []
      )
    )
  }

  host_entrypoints = merge(flatten([
    for hostname in local.host_names : {
      for container in local.host_containers_map[hostname] :
      hostname => container.name if container.web_entrypoint == true
    }
  ])...)

  host_logoutpoints = {
    for hostname, config in local.auth_enabled_hosts : hostname => {
      domain       = try(aws_cognito_user_pool.host_based[hostname].domain, (local.create_user_pool ? aws_cognito_user_pool.user_pool[0].domain : ""))
      client_id    = try(aws_cognito_user_pool_client.host_based[hostname].id, (local.create_user_pool ? aws_cognito_user_pool_client.user_pool[0].id : ""))
      hostname     = ".auth.${var.region}.amazoncognito.com"
      path         = "/logout"
      callback_url = config.callback_url
    }
  }

  balancer_target_groups = {
    for hostname in local.host_names : hostname => merge(
      contains(keys(local.auth_enabled_hosts), hostname) && try(local.auth_enabled_hosts[hostname].automated, false) ? {
        userinfo_endpoint = {
          name_prefix                        = "lauth-"
          target_type                        = "lambda"
          lambda_multi_value_headers_enabled = false
          target_id                          = module.auth_lambda[hostname].lambda_function.arn
          attach_lambda_permission           = true
        }
      } : {},
      {
        for container in local.host_containers_map[hostname] : container.name => {
          name                              = "${local.stage_name}-${container.name}"
          protocol                          = container.protocol
          port                              = container.port
          target_type                       = "ip"
          create_attachment                 = false
          deregistration_delay              = 10
          load_balancing_algorithm_type     = "round_robin"
          load_balancing_anomaly_mitigation = "on"
          load_balancing_cross_zone_enabled = "use_load_balancer_configuration"

          health_check = {
            enabled             = true
            interval            = try(container.health_check.interval, 30)
            path                = try(container.health_check.path, container.web_path)
            port                = "traffic-port"
            healthy_threshold   = 5
            unhealthy_threshold = 2
            timeout             = try(container.health_check.timeout, 5)
            protocol            = container.protocol
            matcher             = try(container.health_check.response_codes, "200")
          }
        }
    })
  }

  balancer_rules = {
    for hostname in local.host_names : hostname => merge(
      contains(keys(local.auth_enabled_hosts), hostname) && try(local.auth_enabled_hosts[hostname].automated, false) ? {
        logout_endpoint = {
          priority = index(local.web_paths[hostname], local.auth_enabled_hosts[hostname].service_endpoints.logout) + 1
          actions = [{
            type        = "redirect"
            status_code = "HTTP_302"
            host        = "${local.host_logoutpoints[hostname].domain}${local.host_logoutpoints[hostname].hostname}"
            path        = local.host_logoutpoints[hostname].path
            query       = "client_id=${local.host_logoutpoints[hostname].client_id}&logout_uri=${urlencode("https://${hostname}.${var.domain_name}")}"
            protocol    = "HTTPS"
          }]

          conditions = [{
            path_pattern = {
              values = [local.auth_enabled_hosts[hostname].service_endpoints.logout]
            }
          }]
        }
        userinfo_endpoint = {
          priority = index(local.web_paths[hostname], local.auth_enabled_hosts[hostname].service_endpoints.userinfo) + 1
          actions = [
            {
              type                       = "authenticate-cognito"
              on_unauthenticated_request = "authenticate"
              session_cookie_name        = "AWSELBSession-${hostname}"
              session_timeout            = 3600
              user_pool_arn              = contains(local.host_based_user_pools, hostname) ? aws_cognito_user_pool.host_based[hostname].arn : (local.create_user_pool ? aws_cognito_user_pool.user_pool[0].arn : "")
              user_pool_client_id        = try(aws_cognito_user_pool_client.host_based[hostname].id, (local.create_user_pool ? aws_cognito_user_pool_client.user_pool[0].id : ""))
              user_pool_domain           = contains(local.host_based_user_pools, hostname) ? aws_cognito_user_pool.host_based[hostname].domain : (local.create_user_pool ? aws_cognito_user_pool.user_pool[0].domain : "")
            },
            {
              type             = "forward"
              target_group_key = "userinfo_endpoint"
            }
          ]
          conditions = [{
            path_pattern = {
              values = [local.auth_enabled_hosts[hostname].service_endpoints.userinfo]
            }
          }]
        }
      }
      : {},
      {
        for container in local.host_containers_map[hostname] : container.name => {
          priority = index(local.web_paths[hostname], container.web_path) + 1

          actions = concat(
            (container.user_auth != null && try(container.user_auth.automated, false) == true) || try(local.auth_enabled_hosts[hostname].automated, false) == true ? [{
              type                       = "authenticate-cognito"
              on_unauthenticated_request = "authenticate"
              session_cookie_name        = "AWSELBSession-${hostname}"
              session_timeout            = 3600
              user_pool_arn              = local.replacements[container.name]["{cognito_user_pool_arn}"]
              user_pool_client_id        = local.replacements[container.name]["{cognito_client_id}"]
              user_pool_domain           = local.replacements[container.name]["{cognito_user_pool_domain}"]
            }] : [],
            [{
              type             = "forward"
              target_group_key = container.name
            }]
          )

          conditions = [{
            path_pattern = {
              values = [
                container.web_path,
                "${trimsuffix(container.web_path, "/")}/*"
              ]
            }
          }]
        }
      }
    )
  }
}

resource "tls_private_key" "root-ca" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "root-ca" {
  private_key_pem = tls_private_key.root-ca.private_key_pem

  subject {
    common_name  = "${local.stage_name} Root CA"
    organization = "${local.stage_name} AWS Root CA"
  }

  validity_period_hours = 24 * 365 * 10
  early_renewal_hours   = 24 * 31 * 4

  is_ca_certificate = true

  allowed_uses = [
    "cert_signing",
    "crl_signing"
  ]
}

resource "tls_private_key" "ssl" {
  algorithm = var.ssl_certificate.key_algorithm
  rsa_bits  = var.ssl_certificate.key_length
}

resource "tls_cert_request" "ssl" {
  dns_names = [
    var.domain_name,
    "*.${var.domain_name}"
  ]
  private_key_pem = tls_private_key.ssl.private_key_pem

  subject {
    common_name  = var.domain_name
    organization = var.ssl_certificate.organization
  }
}

resource "tls_locally_signed_cert" "ssl" {
  cert_request_pem   = tls_cert_request.ssl.cert_request_pem
  ca_cert_pem        = tls_self_signed_cert.root-ca.cert_pem
  ca_private_key_pem = tls_self_signed_cert.root-ca.private_key_pem

  validity_period_hours = 24 * 365 * 9
  early_renewal_hours   = 24 * 31 * 4

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth"
  ]
}

resource "aws_acm_certificate" "trusted_cert" {
  domain_name               = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}"]
  validation_method         = "DNS"

  tags = local.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate" "self_signed_cert" {
  private_key      = tls_private_key.ssl.private_key_pem
  certificate_body = tls_locally_signed_cert.ssl.cert_pem

  tags = local.tags
}

module "ecs_alb" {
  for_each = toset(local.host_names)
  source   = "terraform-aws-modules/alb/aws"
  version  = "9.5.0"

  name    = "${local.stage_name}-${each.value}"
  vpc_id  = module.vpc.vpc_id
  subnets = module.vpc.public_subnets

  # For example only
  enable_deletion_protection = false

  # Security Group
  security_group_ingress_rules = {
    all_http = {
      from_port   = 80
      to_port     = 80
      ip_protocol = "tcp"
      description = "HTTP traffic"
      cidr_ipv4   = "0.0.0.0/0"
    }
    all_https = {
      from_port   = 443
      to_port     = 443
      ip_protocol = "tcp"
      description = "HTTPS traffic"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }
  security_group_egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  access_logs = {
    bucket  = var.access_logs_bucket_id
    prefix  = "ecs-alb-access-logs"
    enabled = true
  }

  connection_logs = {
    bucket  = var.access_logs_bucket_id
    prefix  = "ecs-alb-connection-logs"
    enabled = true
  }

  listeners = {
    http = {
      port     = 80
      protocol = "HTTP"
      redirect = {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }

    https = merge({
      port            = 443
      protocol        = "HTTPS"
      ssl_policy      = "ELBSecurityPolicy-TLS13-1-2-2021-06"
      certificate_arn = var.ssl_certificate.self_signed ? aws_acm_certificate.self_signed_cert.arn : aws_acm_certificate.trusted_cert.arn

      forward = {
        target_group_key = try(local.host_entrypoints[each.key], "error")
      }

      rules = local.balancer_rules[each.key]
      },
      contains(keys(local.auth_enabled_hosts), each.key) && try(local.auth_enabled_hosts[each.key].automated, false) ? merge({
        authenticate_cognito = {
          authentication_request_extra_params = {
            display = "page"
            prompt  = "login"
          }
          on_unauthenticated_request = "authenticate"
          session_cookie_name        = "AWSELBSession-${each.key}"
          session_timeout            = 3600
          user_pool_arn              = try(aws_cognito_user_pool.host_based[each.key].arn, aws_cognito_user_pool.user_pool[0].arn)
          user_pool_client_id        = try(aws_cognito_user_pool_client.host_based[each.key].id, aws_cognito_user_pool_client.user_pool[0].id)
          user_pool_domain           = try(aws_cognito_user_pool.host_based[each.key].domain, aws_cognito_user_pool.user_pool[0].domain)
        }
      }, {}) : {}
    )
  }

  target_groups = local.balancer_target_groups[each.key]

  tags = merge(local.tags,
    { Name = "${local.stage_name}-ecs-alb-${each.value}" }
  )
}

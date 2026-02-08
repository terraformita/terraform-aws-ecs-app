locals {
  # Priority map for standard AWS Managed Rules to ensure correct order
  waf_rule_priorities = {
    "AWSManagedRulesAmazonIpReputationList" = 10
    "AWSManagedRulesKnownBadInputsRuleSet"  = 20
    "AWSManagedRulesSQLiRuleSet"            = 30
    "AWSManagedRulesLinuxRuleSet"           = 40
    "AWSManagedRulesUnixRuleSet"            = 50
    "AWSManagedRulesCommonRuleSet"          = 60
  }

  waf_rules = [
    for i, name in sort(keys(var.waf_config["aws-managed-rules"])) : {
      name        = name
      vendor_name = "AWS"
      # Use known priority or fallback to alphabetical index offset (100+)
      priority = lookup(local.waf_rule_priorities, name, 100 + (i * 10))
      version  = null
      action   = { block = {} }
      statement = {
        name        = name
        vendor_name = "AWS"
        rule_action_override = {
          for rule_name in var.waf_config["aws-managed-rules"][name] : rule_name => {
            action = "count"
          }
        }
      }
      visibility_config = {
        cloudwatch_metrics_enabled = true
        metric_name                = name
        sampled_requests_enabled   = true
      }
    }
  ]
}

module "waf" {
  source  = "cloudposse/waf/aws"
  version = "~> 1.11.0"

  count = var.load_balancer.waf_enabled ? 1 : 0

  name = "${var.stage_name}-waf"

  scope = "REGIONAL"

  default_action = "allow"

  managed_rule_group_statement_rules = local.waf_rules

  # https://docs.aws.amazon.com/waf/latest/developerguide/logging-cw-logs.html#logging-cw-logs-naming
  log_destination_configs = var.waf_logging_enabled ? [module.waf_log_group[0].cloudwatch_log_group_arn] : []

  tags = var.tags

  visibility_config = {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.stage_name}-waf-metric"
    sampled_requests_enabled   = true
  }
}

module "waf_log_group" {
  source  = "terraform-aws-modules/cloudwatch/aws//modules/log-group"
  version = "~> 5.0"

  count = var.load_balancer.waf_enabled && var.waf_logging_enabled ? 1 : 0

  name              = "aws-waf-logs-${var.stage_name}-waf"
  retention_in_days = try(var.waf_logging_config.retention_in_days, 7)
  kms_key_id        = try(var.waf_logging_config.kms_key_id, null)

  tags = var.tags
}

data "aws_iam_policy_document" "waf_log_policy" {
  count = var.load_balancer.waf_enabled && var.waf_logging_enabled ? 1 : 0

  statement {
    effect = "Allow"
    principals {
      type = "Service"
      identifiers = [
        "delivery.logs.amazonaws.com",
        "wafv2.amazonaws.com"
      ]
    }
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["${module.waf_log_group[0].cloudwatch_log_group_arn}:*"]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:logs:${var.region}:${data.aws_caller_identity.current.account_id}:*"]
    }
  }
}

resource "aws_cloudwatch_log_resource_policy" "waf" {
  count = var.load_balancer.waf_enabled && var.waf_logging_enabled ? 1 : 0

  policy_name     = "aws-waf-logs-${var.stage_name}-policy"
  policy_document = data.aws_iam_policy_document.waf_log_policy[0].json
}

resource "aws_wafv2_web_acl_association" "this" {
  for_each = var.load_balancer.waf_enabled ? module.ecs_alb : {}

  resource_arn = each.value.arn
  web_acl_arn  = module.waf[0].arn
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

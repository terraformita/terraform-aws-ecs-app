module "vpc" {
  count   = var.create_vpc ? 1 : 0
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.2.0"

  name             = var.config.name
  cidr             = var.config.vpc_cidr_block
  azs              = var.config.azs
  public_subnets   = var.config.public_subnets
  private_subnets  = var.config.private_subnets
  database_subnets = var.config.database_subnets

  database_subnet_group_name = var.config.database_subnet_group_name

  single_nat_gateway           = var.config.single_nat_gateway
  create_database_subnet_group = var.config.create_database_subnet_group

  enable_dns_hostnames = var.config.enable_dns_hostnames
  enable_dns_support   = var.config.enable_dns_support
  enable_nat_gateway   = var.config.enable_nat_gateway

  enable_dhcp_options = var.config.enable_dhcp_options

  public_subnet_tags  = var.config.public_subnet_tags
  private_subnet_tags = var.config.private_subnet_tags

  tags = var.config.tags
}

data "aws_region" "current" {}

module "endpoints" {
  count = var.create_vpc ? 1 : 0

  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "3.14.2"

  vpc_id = module.vpc[0].vpc_id

  endpoints = {
    s3 = {
      service         = "s3"
      service_type    = "Gateway"
      route_table_ids = flatten([module.vpc[0].private_route_table_ids, module.vpc[0].public_route_table_ids])
      policy          = data.aws_iam_policy_document.generic-endpoint[0].json
      tags = merge(
        var.config.tags,
        {
          Name         = "${var.config.name} S3 VPC endpoint"
          vpc-endpoint = "s3"
        }
      )
    }
  }
  tags = var.config.tags
}

data "aws_iam_policy_document" "generic-endpoint" {
  count = var.create_vpc ? 1 : 0

  statement {
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions   = ["*"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceVpc"
      values   = [module.vpc[0].vpc_id]
    }
    effect = "Allow"
  }

  statement {
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions   = ["*"]
    resources = ["*"]
    condition {
      test     = "StringNotEquals"
      variable = "aws:SourceVpc"
      values   = [module.vpc[0].vpc_id]
    }
    effect = "Deny"
  }

  statement {
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions = ["*"]
    resources = [
      "arn:aws:s3:::repo.${data.aws_region.current.name}.amazonaws.com",
      "arn:aws:s3:::repo.${data.aws_region.current.name}.amazonaws.com/*"
    ]
    effect = "Allow"
  }
}

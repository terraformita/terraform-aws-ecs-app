######## VPC
module "vpc" {
  source = "./modules/vpc"

  create_vpc = var.vpc.vpc_id == null

  config = {
    vpc_id = var.vpc.vpc_id

    name             = "${local.stage_name}-vpc"
    cidr             = var.vpc.cidr
    azs              = var.vpc.azs
    public_subnets   = var.vpc.public_subnets
    private_subnets  = var.vpc.private_subnets
    database_subnets = var.vpc.database_subnets

    db_subnet_group_name    = var.vpc.db_subnet_group_name
    public_route_table_ids  = var.vpc.public_route_table_ids
    private_route_table_ids = var.vpc.private_route_table_ids
    public_subnet_ids       = var.vpc.public_subnet_ids
    private_subnet_ids      = var.vpc.private_subnet_ids

    single_nat_gateway           = true
    create_database_subnet_group = true

    enable_dns_hostnames = true
    enable_dns_support   = true
    enable_nat_gateway   = true

    enable_dhcp_options = true

    public_subnet_tags  = { network = "public" }
    private_subnet_tags = { network = "private" }

    tags = local.tags
  }
}

moved {
  from = module.endpoints
  to   = module.endpoints[0]
}

module "endpoints" {
  count   = var.vpc.vpc_id == null ? 1 : 0
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "3.14.2"

  vpc_id = module.vpc.vpc_id

  endpoints = {
    s3 = {
      service         = "s3"
      service_type    = "Gateway"
      route_table_ids = flatten([module.vpc.private_route_table_ids, module.vpc.public_route_table_ids])
      policy          = data.aws_iam_policy_document.generic-endpoint[0].json
      tags = merge(
        local.tags,
        {
          Name         = "${local.stage_name} S3 VPC endpoint"
          vpc-endpoint = "s3"
        }
      )
    }
  }
  tags = local.tags
}

data "aws_iam_policy_document" "generic-endpoint" {
  count = var.vpc.vpc_id == null ? 1 : 0

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
      values   = [module.vpc.vpc_id]
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
      values   = [module.vpc.vpc_id]
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
      "arn:aws:s3:::repo.${var.region}.amazonaws.com",
      "arn:aws:s3:::repo.${var.region}.amazonaws.com/*"
    ]
    effect = "Allow"
  }
}

module "vpc" {
  count   = var.create_vpc ? 1 : 0
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.2.0"

  name             = var.config.name
  cidr             = var.config.cidr
  azs              = var.config.azs
  public_subnets   = var.config.public_subnets
  private_subnets  = var.config.private_subnets
  database_subnets = var.config.database_subnets

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

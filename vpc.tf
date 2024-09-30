######## VPC
module "vpc" {
  source = "./modules/vpc"

  create_vpc = var.vpc.vpc_id == null

  config = {
    vpc_id = var.vpc.vpc_id

    name             = "${local.stage_name}-vpc"
    vpc_cidr_block   = var.vpc.vpc_cidr_block
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

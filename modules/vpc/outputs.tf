output "vpc_id" {
  value = var.create_vpc ? module.vpc[0].vpc_id : var.config.vpc_id
}

output "vpc_cidr_block" {
  value = var.create_vpc ? module.vpc[0].vpc_cidr_block : var.config.vpc_cidr_block
}

output "public_subnets" {
  value = var.create_vpc ? module.vpc[0].public_subnets : var.config.public_subnets
}

output "private_subnets" {
  value = var.create_vpc ? module.vpc[0].private_subnets : var.config.private_subnets
}

output "database_subnets" {
  value = var.create_vpc ? module.vpc[0].database_subnets : var.config.database_subnets
}

output "database_subnet_group_name" {
  value = var.create_vpc ? module.vpc[0].database_subnet_group_name : var.config.database_subnet_group_name
}

output "public_route_table_ids" {
  value = var.create_vpc ? module.vpc[0].public_route_table_ids : var.config.public_route_table_ids
}

output "private_route_table_ids" {
  value = var.create_vpc ? module.vpc[0].private_route_table_ids : var.config.private_route_table_ids
}

variable "config" {
  type = object({
    name             = string
    cidr             = string
    azs              = list(string)
    public_subnets   = optional(list(string))
    private_subnets  = optional(list(string))
    database_subnets = optional(list(string))

    vpc_id                  = optional(string)
    db_subnet_group_name    = optional(string)
    public_route_table_ids  = optional(list(string))
    private_route_table_ids = optional(list(string))
    private_subnet_ids      = optional(list(string))
    public_subnet_ids       = optional(list(string))

    single_nat_gateway           = bool
    create_database_subnet_group = bool

    enable_dns_hostnames = bool
    enable_dns_support   = bool
    enable_nat_gateway   = bool

    enable_dhcp_options = bool

    public_subnet_tags  = map(string)
    private_subnet_tags = map(string)
    tags                = map(string)
  })
}

variable "create_vpc" {
  type    = bool
  default = true
}

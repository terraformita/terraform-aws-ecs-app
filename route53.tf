resource "aws_route53_record" "a" {
  for_each = (var.manage_dns && var.zone_id != "") ? toset(local.host_names) : []

  zone_id = var.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = module.ecs_alb[each.key].dns_name
    zone_id                = module.ecs_alb[each.key].zone_id
    evaluate_target_health = false
  }
}

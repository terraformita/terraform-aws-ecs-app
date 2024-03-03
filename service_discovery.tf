#### SERVICE DISCOVERY NAMESPACE
resource "aws_service_discovery_http_namespace" "internal" {
  name        = var.stage_name
  description = "Domain name for service discovery"
}

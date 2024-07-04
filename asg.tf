### ECS WITH AUTOSCALING GROUP
locals {
  user_data = <<-EOT
    #!/bin/bash
    cat <<'EOF' >> /etc/ecs/ecs.config
    ECS_CLUSTER=${local.ecs_cluster_name}
    ECS_LOGLEVEL=debug
    EOF
  EOT
}

#### SECURITY GROUP
module "ecs_security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "4.8.0"

  name   = "${local.stage_name}-ecs-sg"
  vpc_id = module.vpc.vpc_id

  ingress_with_cidr_blocks = concat([
    for name, container in local.app_containers_map :
    {
      from_port   = container.port
      to_port     = container.port
      protocol    = "tcp"
      description = "ECS backend container connection"
      cidr_blocks = var.vpc.cidr
    }
  ])

  egress_cidr_blocks = ["0.0.0.0/0"]
  egress_rules       = ["all-all"]

  tags = local.tags
}

################################################################################
# Supporting Resources
################################################################################
# https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-optimized_AMI.html#ecs-optimized-ami-linux
data "aws_ssm_parameter" "ecs_optimized_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended" # "/aws/service/ecs/optimized-ami/amazon-linux-2023/arm64/recommended"
}

#### AUTO-SCALING GROUP
module "autoscaling" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "~> 6.5"

  for_each = {
    "ecs" = var.autoscaling_instances
  }

  name = "${local.stage_name}-asg-${each.key}"

  image_id      = jsondecode(data.aws_ssm_parameter.ecs_optimized_ami.value)["image_id"]
  instance_type = each.value.instance_type

  instance_market_options = {
    market_type = each.value.use_spot_instances == false ? "" : "spot"

    spot_options = {
      max_price          = each.value.use_spot_instances == false ? 0 : each.value.spot_instance_price
      spot_instance_type = "one-time"
    }
  }

  security_groups                 = [module.ecs_security_group.security_group_id]
  user_data                       = base64encode(local.user_data)
  ignore_desired_capacity_changes = true

  create_iam_instance_profile = true
  iam_role_name               = local.stage_name
  iam_role_description        = "ECS role for ${local.stage_name}"
  iam_role_policies = {
    AmazonEC2ContainerServiceforEC2Role = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
    AmazonSSMManagedInstanceCore        = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  # This is to increase ENI density for ECS tasks (otherwise, 3 ENIs per instance is maximum)
  private_dns_name_options = {
    enable_resource_name_dns_a_record = false
    hostname_type                     = "ip-name"
  }

  vpc_zone_identifier = module.vpc.private_subnets
  health_check_type   = "EC2"
  min_size            = var.autoscaling_instances.min
  max_size            = var.autoscaling_instances.max
  desired_capacity    = var.autoscaling_instances.desired

  # https://github.com/hashicorp/terraform-provider-aws/issues/12582
  autoscaling_group_tags = {
    AmazonECSManaged = true
  }

  # Required for managed_termination_protection = "ENABLED"
  protect_from_scale_in = true

  tags = local.tags
}

resource "aws_cloudwatch_log_group" "autoscaling" {
  name = "/aws/ecs/${local.stage_name}-autoscaling"

  retention_in_days = 30

  tags = local.tags
}

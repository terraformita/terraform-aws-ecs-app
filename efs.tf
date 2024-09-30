resource "aws_security_group" "efs_sg" {
  count       = local.create_efs ? 1 : 0
  name        = "${local.stage_name}-efs-security-group"
  description = "Security group for Amazon EFS"

  vpc_id = module.vpc.vpc_id

  // Add inbound and outbound rules as needed to control network traffic
  ingress {
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [module.vpc.vpc_cidr_block]
    description = "NFS (EFS) port"
  }
  // Egress rules allowing all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"          # Represents all protocols
    cidr_blocks = ["0.0.0.0/0"] # Allow all outbound traffic
    description = "Allow all outbound traffic"
  }
}

resource "aws_efs_file_system" "efs_file_system" {
  count            = local.create_efs ? 1 : 0
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"
  encrypted        = true
  lifecycle_policy {
    transition_to_ia = "AFTER_7_DAYS"
  }
}

resource "aws_efs_mount_target" "efs_mount_target" {
  count           = local.create_efs ? length(module.vpc.private_subnets) : 0
  file_system_id  = aws_efs_file_system.efs_file_system[0].id
  subnet_id       = module.vpc.private_subnets[count.index]
  security_groups = [aws_security_group.efs_sg[0].id]
}

resource "aws_efs_access_point" "efs_file_system" {
  for_each = {
    for container, config in local.app_containers_map :
    container => config.disk_drive if config.disk_drive.enabled
  }

  file_system_id = aws_efs_file_system.efs_file_system[0].id
  posix_user {
    uid = each.value.uid
    gid = each.value.gid
  }

  root_directory {
    path = "/${each.key}"
    creation_info {
      owner_uid   = each.value.uid
      owner_gid   = each.value.gid
      permissions = "755"
    }
  }
}

### ECS IAM POLICIES
resource "aws_iam_role" "execution_role" {
  name = "${local.stage_name}-ecs-exec-role"
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [{
      "Sid" : "AssumeRoleECSTaskRole",
      "Effect" : "Allow",
      "Action" : ["sts:AssumeRole"],
      "Principal" : {
        "Service" : "ecs-tasks.amazonaws.com"
      }
    }]
  })
}

data "aws_iam_policy_document" "execution_role_policy" {
  version = "2012-10-17"

  statement {
    sid    = "AllowECRPull"
    effect = "Allow"

    actions = [
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:BatchCheckLayerAvailability",
    ]

    resources = [for repo in aws_ecr_repository.container_repository : repo.arn]
  }

  statement {
    sid    = "AllowECRAuth"
    effect = "Allow"

    actions = [
      "ecr:GetAuthorizationToken",
    ]

    resources = ["*"]
  }


  # TODO: restrict to specific file system and access points
  dynamic "statement" {
    for_each = local.create_efs ? [1] : []

    content {
      sid    = "AllowEFS"
      effect = "Allow"

      actions = [
        "elasticfilesystem:ClientMount",
        "elasticfilesystem:ClientWrite",
        "elasticfilesystem:DescribeMountTargets",
        "elasticfilesystem:DescribeFileSystems"
      ]

      resources = concat(
        [aws_efs_file_system.efs_file_system[0].arn],
        [for access_point in aws_efs_access_point.efs_file_system : access_point.arn]
      )
    }
  }

  statement {
    sid    = "AllowLogging"
    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = concat([
      for log_group in aws_cloudwatch_log_group.container : log_group.arn
      ], [
      for log_group in aws_cloudwatch_log_group.container : "${log_group.arn}:log-stream:*"
    ])
  }

  statement {
    sid    = "AllowAccessToSecrets"
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue",
    ]

    resources = [
      aws_secretsmanager_secret.app_vars.arn,
      aws_secretsmanager_secret.db_credentials.arn
    ]
  }

  dynamic "statement" {
    for_each = length(local.secret_params) > 0 ? [1] : []

    content {
      sid    = "AllowAccessToSSMParameters"
      effect = "Allow"

      actions = [
        "ssm:GetParameters",
        "ssm:GetParameter",
      ]

      resources = [
        for secret, config in local.secret_params :
        try(aws_ssm_parameter.secret[secret].arn, aws_ssm_parameter.secret_placeholder[secret].arn)
      ]
    }
  }
}

resource "aws_iam_role_policy" "execution_role" {
  role   = aws_iam_role.execution_role.name
  policy = data.aws_iam_policy_document.execution_role_policy.json
}

resource "aws_iam_role" "task_role" {
  for_each = local.app_containers_map
  name     = "${local.stage_name}-ecs-task-role-${each.key}"
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [{
      "Sid" : "AssumeRoleECSTaskRole",
      "Effect" : "Allow",
      "Action" : ["sts:AssumeRole"],
      "Principal" : {
        "Service" : "ecs-tasks.amazonaws.com"
      }
    }]
  })
}

data "aws_iam_policy_document" "task_role_policy" {
  for_each = local.app_containers_map
  version  = "2012-10-17"

  statement {
    sid    = "AllowDescribeCluster"
    effect = "Allow"

    actions = [
      "ecs:DescribeClusters",
    ]

    resources = [
      local.ecs_cluster_arn,
    ]
  }

  statement {
    sid    = "AllowLogging"
    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = concat([
      for log_group in aws_cloudwatch_log_group.container : log_group.arn
      ], [
      for log_group in aws_cloudwatch_log_group.container : "${log_group.arn}:log-stream:*"
    ])
  }

  dynamic "statement" {
    for_each = length(each.value.accessible_cloud_storage) > 0 ? [1] : []

    content {
      sid    = "AccessToBuckets"
      effect = "Allow"

      actions = [
        "s3:GetBucketList",
        "s3:GetBucketLocation",
        "s3:ListBucketMultipartUploads",
      ]

      resources = [
        for bucket in each.value.accessible_cloud_storage : bucket
      ]
    }
  }

  dynamic "statement" {
    for_each = length(each.value.accessible_cloud_storage) > 0 ? [1] : []

    content {
      sid    = "AllowReadWriteOnBuckets"
      effect = "Allow"

      actions = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListMultipartUploadParts",
        "s3:AbortMultipartUpload",
      ]

      resources = [
        for bucket in each.value.accessible_cloud_storage : "${bucket}/*"
      ]
    }
  }

  dynamic "statement" {
    for_each = length([
      for secret, value in local.container_secrets[each.key] :
      try(aws_ssm_parameter.secret[secret].arn, aws_ssm_parameter.secret_placeholder[secret].arn)
    ]) > 0 ? [1] : []

    content {
      sid    = "AllowAccessToSSMParameters"
      effect = "Allow"

      actions = [
        "ssm:GetParameters",
        "ssm:GetParameter",
      ]

      resources = [
        for secret, value in local.container_secrets[each.key] :
        try(aws_ssm_parameter.secret[secret].arn, aws_ssm_parameter.secret_placeholder[secret].arn)
      ]
    }
  }
}

resource "aws_iam_role_policy" "task_role" {
  for_each = local.app_containers_map
  role     = aws_iam_role.task_role[each.key].name
  policy   = data.aws_iam_policy_document.task_role_policy[each.key].json
}

#### COGNITO USER POOL ROLE
resource "aws_iam_role" "user_pool" {
  name = "${local.stage_name}-cognito-user-pool"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRole"
      Principal = {
        Service = "cognito-idp.amazonaws.com"
      }
      Condition = {
        StringEquals = {
          "sts:ExternalId" = local.cognito_sms_external_id
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "cognito_send_sms" {
  name = "${local.stage_name}-cognito-send-sms"
  role = aws_iam_role.user_pool.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sns:Publish"
      Resource = "*"
    }]
  })
}

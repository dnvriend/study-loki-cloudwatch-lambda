resource "aws_ecs_task_definition" "httpbin" {
  family                   = "${local.prefix}-httpbin"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 2 * 1024
  memory                   = 4 * 1024

  execution_role_arn = aws_iam_role.httpbin_ecs_task_execution_role.arn
  task_role_arn      = aws_iam_role.httpbin_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "httpbin"
      image     = "kennethreitz/httpbin"
      essential = true

      environment = [
        {
          name  = "GUNICORN_CMD_ARGS",
          value = "--log-level debug"
        }
      ]

      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
          protocol      = "tcp"
        }
      ]

      linuxParameters = {
        initProcessEnabled = true
      }
      # https://docs.aws.amazon.com/AmazonECS/latest/developerguide/firelens-taskdef.html
      # The key-value pairs specified as options in the logConfiguration object are used to generate the Fluentd or Fluent Bit output configuration.

      # logConfiguration = {
      #   logDriver = "awsfirelens"
      #   options = {
      #     Name       = "loki"
      #     Url        = "http://${aws_lb.loki_lb.dns_name}/loki/api/v1/push"
      #     Labels     = "{env=\"test_labels\",project_id=\"$${PROJECT_ID}\"}"
      #     RemoveKeys = "container_id,ecs_task_arn"
      #     LabelKeys  = "container_name,ecs_task_definition,source,ecs_cluster"
      #     LineFormat = "key_value"
      #   }
      # }

      logConfiguration = {
        logDriver = "awslogs"
        options   = {
          awslogs-group         = aws_cloudwatch_log_group.httpbin_log_group.name
          awslogs-region        = local.region
          awslogs-stream-prefix = "fargate"
        }
      }
    },
    # {
    #   name  = "fluentbit"
    #   image = "grafana/fluent-bit-plugin-loki:2.0.0-amd64"
    #   # image        = "grafana/fluent-bit-plugin-loki:2.9.1" # note that it uses different keys for labels
    #   essential    = true
    #   cpu          = 0
    #   mountPoints  = []
    #   volumesFrom  = []
    #   environment  = []
    #   portMappings = []
    #   user         = "0"
    #
    #   environment = [
    #     {
    #       name  = "PROJECT_ID"
    #       value = "543210"
    #     },
    #   ]
    #
    #   firelensConfiguration = {
    #     type = "fluentbit"
    #     options = {
    #       "enable-ecs-log-metadata" : "true"
    #     }
    #   }
    #
    #   logConfiguration = {
    #     logDriver = "awslogs"
    #     options = {
    #       awslogs-group         = aws_cloudwatch_log_group.httpbin_log_group.name
    #       awslogs-region        = data.aws_region.current.name
    #       awslogs-stream-prefix = "fargate"
    #     }
    #   }
    # },
  ])
}


resource "aws_ecs_service" "httpbin_service" {
  name                   = "${local.prefix}-httpbin-service"
  cluster                = aws_ecs_cluster.ecs_cluster.id
  task_definition        = aws_ecs_task_definition.httpbin.arn
  desired_count          = 1
  platform_version       = "LATEST"
  enable_execute_command = true

  network_configuration {
    subnets = [
      aws_subnet.private_1.id,
      aws_subnet.private_2.id,
      aws_subnet.private_3.id,
    ]
    security_groups  = [aws_security_group.httpbin_task.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.httpbin_tg.arn
    container_name   = "httpbin"
    container_port   = 80
  }

  capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 0
  }

  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200
  health_check_grace_period_seconds  = 30

  lifecycle {
    ignore_changes = [
      desired_count
    ]
  }

  depends_on = [
    aws_lb_target_group.httpbin_tg,
    aws_lb_listener.httpbin_http_listener,
    aws_lb.httpbin_lb,
  ]
}

resource "aws_appautoscaling_target" "httpbin_scaling_target" {
  max_capacity       = 2
  min_capacity       = 1
  resource_id        = "service/${aws_ecs_cluster.ecs_cluster.name}/${aws_ecs_service.httpbin_service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "httpbin_scaling_policy" {
  name               = "httpbin-scaling-policy"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.httpbin_scaling_target.resource_id
  scalable_dimension = aws_appautoscaling_target.httpbin_scaling_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.httpbin_scaling_target.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value = 50.0
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    scale_in_cooldown  = 300
    scale_out_cooldown = 300
  }
}

resource "aws_cloudwatch_log_group" "httpbin_log_group" {
  name              = "${local.prefix}-httpbin-log-group"
  retention_in_days = 7
}

resource "aws_security_group" "httpbin_task" {
  name        = "${local.prefix}-httpbin-task"
  description = "Security group for the httpbin ECS task"
  vpc_id      = aws_vpc.vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    cidr_blocks     = []
    security_groups = [aws_security_group.httpbin_alb.id]
  }
}

# role for the task
resource "aws_iam_role" "httpbin_task_role" {
  name_prefix = "${local.prefix}-httpbin-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

# policy for the task
resource "aws_iam_role_policy" "httpbin_ecs_task_role_policy" {
  name_prefix = "${local.prefix}-httpbin"
  role        = aws_iam_role.httpbin_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "aps:DescribeAlertManagerDefinition",
          "aps:DescribeLoggingConfiguration",
          "aps:DescribeRuleGroupsNamespace",
          "aps:DescribeWorkspace",
          "aps:GetLabels",
          "aps:GetMetricMetadata",
          "aps:GetSeries",
          "aps:ListRuleGroupsNamespaces",
          "aps:ListWorkspaces",
          "aps:QueryMetrics",
          "aps:RemoteWrite",
          "cloudwatch:*",
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:BatchGetImage",
          "ecr:GetAuthorizationToken",
          "ecr:GetDownloadUrlForLayer",
          "ecs:DescribeTasks",
          "ecs:ExecuteCommand",
          "ecs:RunTask",
          "ecs:StartTask",
          "ecs:StopTask",
          "ecs:UpdateService",
          "kms:Decrypt",
          "logs:*",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:DescribeLogStreams",
          "logs:PutLogEvents",
          "logs:PutLogEvents",
          "secretsmanager:GetSecretValue",
          "ssm:DescribeSessions",
          "ssm:GetParameters",
          "ssm:StartSession",
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel",
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "httpbin_ecs_task_execution_role" {
  name_prefix = "${local.prefix}-httpbin-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "httpbin_ecs_task_execution_policy" {
  name_prefix = "${local.prefix}-httpbin-"
  role        = aws_iam_role.httpbin_ecs_task_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "cloudwatch:*",
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:GetAuthorizationToken",
          "ecr:GetDownloadUrlForLayer",
          "ecs:DescribeTasks",
          "ecs:ExecuteCommand",
          "ecs:RunTask",
          "ecs:StartTask",
          "ecs:StopTask",
          "ecs:UpdateService",
          "kms:Decrypt",
          "logs:*",
          "secretsmanager:GetSecretValue",
          "ssm:DescribeSessions",
          "ssm:GetParameters",
          "ssm:StartSession",
        ],
        Resource = "*"
      }
    ]
  })
}

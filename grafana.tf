resource "aws_ecs_task_definition" "grafana" {
  family                   = "${local.prefix}-grafana"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 2 * 1024
  memory                   = 4 * 1024

  execution_role_arn = aws_iam_role.grafana_ecs_task_execution_role.arn
  task_role_arn      = aws_iam_role.grafana_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "grafana"
      image     = "${aws_ecr_repository.ecr_grafana_image.repository_url}:dev"
      essential = true
      environment = [
        # https://github.com/grafana/grafana/blob/main/conf/defaults.ini
        # grafana uses the sqlite database
        {
          "name" : "GF_LOG_LEVEL"
          "value" : "debug"
        },
        {
          "name" : "GF_AUTH_ANONYMOUS_ORG_ROLE"
          "value" : "Admin"
        },
        {
          "name" : "GF_AUTH_ANONYMOUS_ENABLED"
          "value" : "true"
        },
        {
          "name" : "GF_AUTH_BASIC_ENABLED"
          "value" : "false"
        },
        {
          "name" : "AWS_SDK_LOAD_CONFIG"
          "value" : "true"
        },
        {
          "name" : "GF_AUTH_SIGV4_AUTH_ENABLED"
          "value" : "true"
        },
      ]

      portMappings = [
        {
          containerPort = local.grafana_port
          hostPort      = local.grafana_port
          protocol      = "tcp"
        }
      ]

      linuxParameters = {
        initProcessEnabled = true
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.grafana_log_group.name
          awslogs-region        = local.region
          awslogs-stream-prefix = "fargate"
        }
      }
    }
  ])
}


resource "aws_ecs_service" "grafana_service" {
  name                   = "${local.prefix}-grafana-service"
  cluster                = aws_ecs_cluster.ecs_cluster.id
  task_definition        = aws_ecs_task_definition.grafana.arn
  desired_count          = 1
  platform_version       = "LATEST"
  enable_execute_command = true

  network_configuration {
    subnets = [
      aws_subnet.private_1.id,
      aws_subnet.private_2.id,
      aws_subnet.private_3.id,
    ]
    security_groups  = [aws_security_group.grafana_task.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.grafana_tg.arn
    container_name   = "grafana"
    container_port   = local.grafana_port
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
    aws_lb_target_group.grafana_tg,
    aws_lb_listener.grafana_http_listener,
    aws_lb.grafana_lb,
  ]
}

resource "aws_appautoscaling_target" "grafana_scaling_target" {
  max_capacity       = 2
  min_capacity       = 1
  resource_id        = "service/${aws_ecs_cluster.ecs_cluster.name}/${aws_ecs_service.grafana_service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "grafana_scaling_policy" {
  name               = "grafana-scaling-policy"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.grafana_scaling_target.resource_id
  scalable_dimension = aws_appautoscaling_target.grafana_scaling_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.grafana_scaling_target.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value = 50.0
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    scale_in_cooldown  = 300
    scale_out_cooldown = 300
  }
}

resource "aws_cloudwatch_log_group" "grafana_log_group" {
  name              = "${local.prefix}-grafana-log-group"
  retention_in_days = 7
}

resource "aws_security_group" "grafana_task" {
  name        = "${local.prefix}-grafana-task"
  description = "Security group for the grafana ECS task"
  vpc_id      = aws_vpc.vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port       = local.grafana_port
    to_port         = local.grafana_port
    protocol        = "tcp"
    cidr_blocks     = []
    security_groups = [aws_security_group.grafana_alb.id]
  }
}

# role for the task
resource "aws_iam_role" "grafana_task_role" {
  name_prefix = "${local.prefix}-grafana-"

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
resource "aws_iam_role_policy" "grafana_ecs_task_role_policy" {
  name_prefix = "${local.prefix}-grafana"
  role        = aws_iam_role.grafana_task_role.id

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

resource "aws_iam_role" "grafana_ecs_task_execution_role" {
  name_prefix = "${local.prefix}-grafana-"

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

resource "aws_iam_role_policy" "grafana_ecs_task_execution_policy" {
  name_prefix = "${local.prefix}-grafana-"
  role        = aws_iam_role.grafana_ecs_task_execution_role.id

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

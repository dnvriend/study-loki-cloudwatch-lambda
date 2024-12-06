resource "aws_ecs_task_definition" "loki" {
  family                   = "${local.prefix}-loki"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 2 * 1024
  memory                   = 4 * 1024

  execution_role_arn = aws_iam_role.loki_ecs_task_execution_role.arn
  task_role_arn      = aws_iam_role.loki_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "loki"
      image     = "${aws_ecr_repository.ecr_loki_image.repository_url}:dev"
      essential = true
      environment = [
        {
          "name" : "STORAGE_CONFIG_AWS_S3"
          "value" : module.loki_bucket.bucket_id
        },
        {
          "name" : "STORAGE_CONFIG_AWS_REGION"
          "value" : data.aws_region.current.name
        },
      ]

      portMappings = [
        {
          containerPort = local.loki_port
          hostPort      = local.loki_port
          protocol      = "tcp"
        }
      ]

      linuxParameters = {
        initProcessEnabled = true
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.loki_log_group.name
          awslogs-region        = local.region
          awslogs-stream-prefix = "fargate"
        }
      }
    }
  ])
}


resource "aws_ecs_service" "loki_service" {
  name                   = "${local.prefix}-loki-service"
  cluster                = aws_ecs_cluster.ecs_cluster.id
  task_definition        = aws_ecs_task_definition.loki.arn
  desired_count          = 1
  platform_version       = "LATEST"
  enable_execute_command = true

  network_configuration {
    subnets = [
      aws_subnet.private_1.id,
      aws_subnet.private_2.id,
      aws_subnet.private_3.id,
    ]
    security_groups  = [aws_security_group.loki_task.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.loki_tg.arn
    container_name   = "loki"
    container_port   = local.loki_port
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
    aws_lb_target_group.loki_tg,
    aws_lb_listener.loki_http_listener,
    aws_lb.loki_lb,
  ]
}

resource "aws_appautoscaling_target" "loki_scaling_target" {
  max_capacity       = 2
  min_capacity       = 1
  resource_id        = "service/${aws_ecs_cluster.ecs_cluster.name}/${aws_ecs_service.loki_service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "loki_scaling_policy" {
  name               = "loki-scaling-policy"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.loki_scaling_target.resource_id
  scalable_dimension = aws_appautoscaling_target.loki_scaling_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.loki_scaling_target.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value = 50.0
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    scale_in_cooldown  = 300
    scale_out_cooldown = 300
  }
}

resource "aws_cloudwatch_log_group" "loki_log_group" {
  name              = "${local.prefix}-loki-log-group"
  retention_in_days = 7
}

resource "aws_security_group" "loki_task" {
  name        = "${local.prefix}-loki-task"
  description = "Security group for the loki ECS task"
  vpc_id      = aws_vpc.vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port       = local.loki_port
    to_port         = local.loki_port
    protocol        = "tcp"
    cidr_blocks     = []
    security_groups = [aws_security_group.loki_alb.id]
  }
}

# role for the task
resource "aws_iam_role" "loki_task_role" {
  name_prefix = "${local.prefix}-loki-"

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
resource "aws_iam_role_policy" "loki_ecs_task_role_policy" {
  name_prefix = "${local.prefix}-loki"
  role        = aws_iam_role.loki_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:*",
          "ssm:DescribeSessions",
          "ssm:GetParameters",
          "ssm:StartSession",
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel",
          "s3:*",
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "loki_ecs_task_execution_role" {
  name_prefix = "${local.prefix}-loki-"

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

resource "aws_iam_role_policy" "loki_ecs_task_execution_policy" {
  name_prefix = "${local.prefix}-loki-"
  role        = aws_iam_role.loki_ecs_task_execution_role.id

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

module "loki_bucket" {
  source      = "./modules/bucket"
  bucket_name = "${data.aws_caller_identity.current.account_id}-${local.prefix}-loki-bucket"
}

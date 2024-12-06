resource "aws_lb" "grafana_lb" {
  name               = "${local.prefix}-grafana-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.grafana_alb.id]
  subnets = [
    aws_subnet.public_1.id,
    aws_subnet.public_2.id,
    aws_subnet.public_3.id,
  ]
  enable_deletion_protection = false
}

resource "aws_lb_target_group" "grafana_tg" {
  name        = "${local.prefix}-grafana-tg"
  target_type = "ip"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.vpc.id

  health_check {
    port              = local.grafana_port
    path              = "/api/health"
    enabled           = true
    healthy_threshold = 3
    interval          = 10
    matcher           = "200-499"
  }
}

resource "aws_lb_listener" "grafana_http_listener" {
  load_balancer_arn = aws_lb.grafana_lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.grafana_tg.arn
  }
}

resource "aws_security_group" "grafana_alb" {
  name        = "${local.prefix}-grafana-alb-sg"
  description = "Security group for Grafana ALB"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [
      "0.0.0.0/0",
    ]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

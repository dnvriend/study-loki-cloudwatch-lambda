resource "aws_lb" "loki_lb" {
  name               = "${local.prefix}-loki-alb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.loki_alb.id]
  subnets = [
    aws_subnet.private_1.id,
    aws_subnet.private_2.id,
    aws_subnet.private_3.id,
  ]
  enable_deletion_protection = false
}

resource "aws_lb_target_group" "loki_tg" {
  name        = "${local.prefix}-loki-tg"
  target_type = "ip"
  port        = local.loki_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.vpc.id

  health_check {
    port              = local.loki_port
    path              = "/ready"
    enabled           = true
    healthy_threshold = 3
    interval          = 10
    matcher           = "200-499"
  }
}

resource "aws_lb_listener" "loki_http_listener" {
  load_balancer_arn = aws_lb.loki_lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.loki_tg.arn
  }
}

resource "aws_security_group" "loki_alb" {
  name        = "${local.prefix}-loki-alb-sg"
  description = "Security group for Loki ALB"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.vpc.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

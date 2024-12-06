resource "aws_lb" "httpbin_lb" {
  name               = "${local.prefix}-httpbin-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.httpbin_alb.id]
  subnets = [
    aws_subnet.public_1.id,
    aws_subnet.public_2.id,
    aws_subnet.public_3.id,
  ]
  enable_deletion_protection = false
}

resource "aws_lb_target_group" "httpbin_tg" {
  name        = "${local.prefix}-httpbin-tg"
  target_type = "ip"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.vpc.id

  health_check {
    port              = "80"
    path              = "/"
    enabled           = true
    healthy_threshold = 3
    interval          = 10
    matcher           = "200-499"
  }
}

resource "aws_lb_listener" "httpbin_http_listener" {
  load_balancer_arn = aws_lb.httpbin_lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.httpbin_tg.arn
  }
}

resource "aws_security_group" "httpbin_alb" {
  name        = "${local.prefix}-httpbin-alb-sg"
  description = "Security group for httpbin ALB"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

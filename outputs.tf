output "aws_caller_identity" {
  value = data.aws_caller_identity.current
}

output "aws_region" {
  value = data.aws_region.current
}

output "grafana_alb_dns_name" {
  value = aws_lb.grafana_lb.dns_name
}

output "loki_alb_dns_name" {
  value = aws_lb.loki_lb.dns_name
}

output "httpbin_alb_dns_name" {
  value = aws_lb.httpbin_lb.dns_name
}

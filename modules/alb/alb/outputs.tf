output "alb_dns_name" {
  value = aws_lb.alb.dns_name
}

output "target_group_arn" {
  value = aws_lb_target_group.alb.arn
}

output "listener_arn" {
  value = aws_lb_listener.http.arn
}

output "alb_arn" {
  value = aws_lb.alb.arn
}
output "alb_name" {
  value = aws_lb.alb.name
}

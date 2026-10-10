output "prod_url" {
  description = "Production URL (Port 80) served by Blue/Green ALB"
  value       = "http://${module.alb.alb_dns_name}"
}

output "test_url" {
  description = "Test Listener URL (Port 8080) for validating Green fleet before cutover"
  value       = "http://${module.alb.alb_dns_name}:8080"
}

output "ecs_service_name" {
  description = "Name of the ECS Service"
  value       = aws_ecs_service.app.name
}

output "ecs_cluster_name" {
  description = "Name of the ECS Cluster"
  value       = local.cluster_name
}

output "primary_target_group_arn" {
  description = "Blue Target Group ARN"
  value       = module.alb.primary_target_group_arn
}

output "secondary_target_group_arn" {
  description = "Green Target Group ARN"
  value       = module.alb.secondary_target_group_arn
}

output "prod_listener_arn" {
  description = "Production Listener ARN"
  value       = module.alb.prod_listener_arn
}

output "test_listener_arn" {
  description = "Test Listener ARN"
  value       = module.alb.test_listener_arn
}

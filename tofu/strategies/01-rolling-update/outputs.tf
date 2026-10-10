output "alb_dns_name" {
  description = "Public URL of the Rolling Update Application Load Balancer"
  value       = "http://${module.alb.alb_dns_name}"
}

output "ecs_service_name" {
  description = "Name of the ECS Service"
  value       = aws_ecs_service.app.name
}

output "ecs_cluster_name" {
  description = "Name of the ECS Cluster"
  value       = local.cluster_name
}

output "task_family" {
  description = "Task Definition Family"
  value       = aws_ecs_task_definition.initial.family
}

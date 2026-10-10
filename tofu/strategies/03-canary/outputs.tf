output "prod_url" {
  description = "Production URL (Port 80) for Canary testing"
  value       = "http://${module.alb.alb_dns_name}"
}

output "test_url" {
  description = "Test Listener URL (Port 8080) for Green verification before canary shift"
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

output "codedeploy_app_name" {
  description = "Name of the CodeDeploy Application"
  value       = aws_codedeploy_app.app.name
}

output "codedeploy_deployment_group_name" {
  description = "Name of the CodeDeploy Deployment Group"
  value       = aws_codedeploy_deployment_group.group.deployment_group_name
}

output "task_family" {
  description = "Task Definition Family"
  value       = aws_ecs_task_definition.initial.family
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnet_ids
}

output "ecr_repository_url" {
  description = "ECR Repository URL"
  value       = module.ecr.repository_url
}

output "ecr_repository_name" {
  description = "ECR Repository Name"
  value       = module.ecr.repository_name
}

output "ecs_cluster_name" {
  description = "ECS Cluster Name"
  value       = module.ecs_cluster.cluster_name
}

output "ecs_cluster_arn" {
  description = "ECS Cluster ARN"
  value       = module.ecs_cluster.cluster_arn
}

output "execution_role_arn" {
  description = "ECS Task Execution Role ARN"
  value       = module.ecs_cluster.execution_role_arn
}

output "task_role_arn" {
  description = "ECS Task Role ARN"
  value       = module.ecs_cluster.task_role_arn
}

output "task_security_group_id" {
  description = "Security Group ID for ECS Tasks"
  value       = module.ecs_cluster.tasks_security_group_id
}

output "github_actions_role_arn" {
  description = "IAM Role ARN for GitHub Actions OIDC"
  value       = module.oidc.role_arn
}

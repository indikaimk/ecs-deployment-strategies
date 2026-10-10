terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "cluster_name" {
  description = "Name of the ECS cluster"
  type        = string
  default     = "ecs-deployment-demo-cluster"
}

variable "vpc_id" {
  description = "VPC ID where ECS tasks run"
  type        = string
}

variable "log_retention_days" {
  description = "Retention period for CloudWatch logs in days"
  type        = number
  default     = 7
}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = var.cluster_name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name      = var.cluster_name
    ManagedBy = "OpenTofu"
  }
}

resource "aws_ecs_cluster_capacity_providers" "providers" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "ecs_logs" {
  name              = "/ecs/${var.cluster_name}"
  retention_in_days = var.log_retention_days

  tags = {
    ManagedBy = "OpenTofu"
  }
}

# IAM Task Execution Role (Pulls images, pushes logs)
data "aws_iam_policy_document" "ecs_tasks_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "task_execution" {
  name               = "${var.cluster_name}-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json

  tags = {
    ManagedBy = "OpenTofu"
  }
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# IAM Task Role (Permissions for the running container process)
resource "aws_iam_role" "task" {
  name               = "${var.cluster_name}-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json

  tags = {
    ManagedBy = "OpenTofu"
  }
}

# Security Group for ECS Tasks
resource "aws_security_group" "ecs_tasks" {
  name        = "${var.cluster_name}-tasks-sg"
  description = "Security group for ECS tasks"
  vpc_id      = var.vpc_id

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name      = "${var.cluster_name}-tasks-sg"
    ManagedBy = "OpenTofu"
  }
}

# Outputs
output "cluster_id" {
  description = "ID of the ECS cluster"
  value       = aws_ecs_cluster.main.id
}

output "cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = aws_ecs_cluster.main.arn
}

output "execution_role_arn" {
  description = "ARN of the ECS Task Execution Role"
  value       = aws_iam_role.task_execution.arn
}



output "task_role_arn" {
  description = "ARN of the ECS Task Role"
  value       = aws_iam_role.task.arn
}

output "log_group_name" {
  description = "Name of the CloudWatch Log Group"
  value       = aws_cloudwatch_log_group.ecs_logs.name
}

output "tasks_security_group_id" {
  description = "Security group ID for ECS tasks"
  value       = aws_security_group.ecs_tasks.id
}

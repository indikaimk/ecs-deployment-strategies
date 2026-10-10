terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "ecs-deployment-strategies"
      Strategy    = "rolling-update"
      Environment = var.environment
      ManagedBy   = "OpenTofu"
    }
  }
}

# Read state from the foundation layer
data "terraform_remote_state" "foundation" {
  backend = "local"
  config = {
    path = "../../foundation/terraform.tfstate"
  }
}

locals {
  vpc_id                  = data.terraform_remote_state.foundation.outputs.vpc_id
  public_subnet_ids       = data.terraform_remote_state.foundation.outputs.public_subnet_ids
  cluster_name            = data.terraform_remote_state.foundation.outputs.ecs_cluster_name
  cluster_arn             = data.terraform_remote_state.foundation.outputs.ecs_cluster_arn
  execution_role_arn      = data.terraform_remote_state.foundation.outputs.execution_role_arn
  task_role_arn           = data.terraform_remote_state.foundation.outputs.task_role_arn
  task_security_group_id  = data.terraform_remote_state.foundation.outputs.task_security_group_id
  ecr_repository_url      = data.terraform_remote_state.foundation.outputs.ecr_repository_url
}

# 1. Dedicated Application Load Balancer (Single Target Group for Rolling)
module "alb" {
  source             = "../../modules/alb"
  name               = "rolling-${var.environment}"
  vpc_id             = local.vpc_id
  public_subnet_ids  = local.public_subnet_ids
  dual_target_groups = false
}

# Allow ALB to reach tasks on port 3000
resource "aws_security_group_rule" "alb_to_tasks" {
  type                     = "ingress"
  from_port                = 3000
  to_port                  = 3000
  protocol                 = "tcp"
  source_security_group_id = module.alb.alb_security_group_id
  security_group_id        = local.task_security_group_id
  description              = "Allow inbound traffic from rolling update ALB to ECS tasks"
}

# 2. Baseline Task Definition (ARM64 Graviton)
resource "aws_ecs_task_definition" "initial" {
  family                   = "demo-rolling-app"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = local.execution_role_arn
  task_role_arn            = local.task_role_arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([
    {
      name      = "web"
      image     = "${local.ecr_repository_url}:latest"
      essential = true
      portMappings = [
        {
          containerPort = 3000
          hostPort      = 3000
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "APP_VERSION", value = "v1.0.0" },
        { name = "APP_COLOR", value = "blue" },
        { name = "APP_RELEASE_TITLE", value = "Rolling Update - v1.0.0 (Baseline)" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${local.cluster_name}"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "rolling"
        }
      }
    }
  ])
}

# 3. ECS Service (Native Rolling Update Controller)
resource "aws_ecs_service" "app" {
  name            = "demo-rolling-service"
  cluster         = local.cluster_arn
  task_definition = aws_ecs_task_definition.initial.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  deployment_controller {
    type = "ECS"
  }

  deployment_minimum_healthy_percent = var.minimum_healthy_percent
  deployment_maximum_percent         = var.maximum_percent

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = local.public_subnet_ids
    security_groups  = [local.task_security_group_id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = module.alb.primary_target_group_arn
    container_name   = "web"
    container_port   = 3000
  }

  # Separation of concerns: GitHub Actions owns application releases & task revisions
  lifecycle {
    ignore_changes = [
      task_definition,
      desired_count
    ]
  }

  depends_on = [aws_security_group_rule.alb_to_tasks]
}

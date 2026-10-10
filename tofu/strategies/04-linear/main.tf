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
      Strategy    = "linear"
      Environment = var.environment
      ManagedBy   = "OpenTofu"
    }
  }
}

data "terraform_remote_state" "foundation" {
  backend = "local"
  config = {
    path = "../../foundation/terraform.tfstate"
  }
}

locals {
  vpc_id                 = data.terraform_remote_state.foundation.outputs.vpc_id
  public_subnet_ids      = data.terraform_remote_state.foundation.outputs.public_subnet_ids
  cluster_name           = data.terraform_remote_state.foundation.outputs.ecs_cluster_name
  cluster_arn            = data.terraform_remote_state.foundation.outputs.ecs_cluster_arn
  execution_role_arn     = data.terraform_remote_state.foundation.outputs.execution_role_arn
  task_role_arn          = data.terraform_remote_state.foundation.outputs.task_role_arn
  task_security_group_id = data.terraform_remote_state.foundation.outputs.task_security_group_id
  ecr_repository_url     = data.terraform_remote_state.foundation.outputs.ecr_repository_url
}

# 1. Dual Target Group Application Load Balancer
module "alb" {
  source               = "../../modules/alb"
  name                 = "linear-${var.environment}"
  vpc_id               = local.vpc_id
  public_subnet_ids    = local.public_subnet_ids
  dual_target_groups   = true
  enable_test_listener = true
}

resource "aws_security_group_rule" "alb_to_tasks" {
  type                     = "ingress"
  from_port                = 3000
  to_port                  = 3000
  protocol                 = "tcp"
  source_security_group_id = module.alb.alb_security_group_id
  security_group_id        = local.task_security_group_id
  description              = "Allow inbound traffic from Linear ALB to ECS tasks"
}

# 2. CloudWatch Metric Alarm for Automated Rollback
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "linear-${var.environment}-5xx-errors"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Rolls back CodeDeploy linear deployment if HTTP 5xx errors occur"

  dimensions = {
    LoadBalancer = split("/", module.alb.alb_arn)[1] == "loadbalancer" ? join("/", slice(split("/", module.alb.alb_arn), 1, 4)) : module.alb.alb_arn
  }

  tags = {
    ManagedBy = "OpenTofu"
  }
}

# 3. IAM Role for CodeDeploy
data "aws_iam_policy_document" "codedeploy_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["codedeploy.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "codedeploy" {
  name               = "linear-${var.environment}-codedeploy-role"
  assume_role_policy = data.aws_iam_policy_document.codedeploy_assume_role.json

  tags = {
    ManagedBy = "OpenTofu"
  }
}

resource "aws_iam_role_policy_attachment" "codedeploy" {
  role       = aws_iam_role.codedeploy.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS"
}

# 4. CodeDeploy Application & Deployment Group
resource "aws_codedeploy_app" "app" {
  compute_platform = "ECS"
  name             = "linear-${var.environment}-app"
}

resource "aws_codedeploy_deployment_group" "group" {
  app_name               = aws_codedeploy_app.app.name
  deployment_group_name  = "linear-${var.environment}-dg"
  service_role_arn       = aws_iam_role.codedeploy.arn
  deployment_config_name = var.linear_config_name

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM"]
  }

  alarm_configuration {
    alarms  = [aws_cloudwatch_metric_alarm.alb_5xx.alarm_name]
    enabled = true
  }

  blue_green_deployment_config {
    terminate_blue_instances_on_deployment_success {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = 5
    }

    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT"
    }
  }

  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "BLUE_GREEN"
  }

  ecs_service {
    cluster_name = local.cluster_name
    service_name = aws_ecs_service.app.name
  }

  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route {
        listener_arns = [module.alb.prod_listener_arn]
      }

      test_traffic_route {
        listener_arns = [module.alb.test_listener_arn]
      }

      target_group {
        name = module.alb.primary_target_group_name
      }

      target_group {
        name = module.alb.secondary_target_group_name
      }
    }
  }

  depends_on = [aws_iam_role_policy_attachment.codedeploy]
}

# 5. Baseline Task Definition (ARM64 Graviton)
resource "aws_ecs_task_definition" "initial" {
  family                   = "demo-linear-app"
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
        { name = "APP_RELEASE_TITLE", value = "Blue Baseline - v1.0.0" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${local.cluster_name}"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "linear"
        }
      }
    }
  ])
}

# 6. ECS Service (Delegated to CodeDeploy)
resource "aws_ecs_service" "app" {
  name            = "demo-linear-service"
  cluster         = local.cluster_arn
  task_definition = aws_ecs_task_definition.initial.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  deployment_controller {
    type = "CODE_DEPLOY"
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

  lifecycle {
    ignore_changes = [
      task_definition,
      desired_count,
      load_balancer
    ]
  }

  depends_on = [aws_security_group_rule.alb_to_tasks]
}

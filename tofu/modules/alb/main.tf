terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "name" {
  description = "Name prefix for the ALB"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the ALB and Target Groups reside"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for the ALB"
  type        = list(string)
}

variable "dual_target_groups" {
  description = "Whether to create dual target groups (Blue and Green) for Blue/Green, Canary, Linear strategies"
  type        = bool
  default     = false
}

variable "enable_test_listener" {
  description = "Whether to create a test listener on port 8080 (for pre-traffic validation of Green fleet)"
  type        = bool
  default     = false
}

variable "health_check_path" {
  description = "Health check path for target groups"
  type        = string
  default     = "/health"
}

variable "deregistration_delay" {
  description = "Time in seconds for ALB to drain connections from deregistered tasks (set low for demos)"
  type        = number
  default     = 15
}

# ALB Security Group
resource "aws_security_group" "alb" {
  name        = "${var.name}-alb-sg"
  description = "Security group for ${var.name} Application Load Balancer"
  vpc_id      = var.vpc_id

  # Production HTTP
  ingress {
    description = "Allow inbound HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Test Listener HTTP (Port 8080) for Blue/Green verification
  dynamic "ingress" {
    for_each = var.enable_test_listener ? [1] : []
    content {
      description = "Allow inbound test traffic from internet on port 8080"
      from_port   = 8080
      to_port     = 8080
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name      = "${var.name}-alb-sg"
    ManagedBy = "OpenTofu"
  }
}

# Application Load Balancer
resource "aws_lb" "main" {
  name               = substr("${var.name}-alb", 0, 32)
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  tags = {
    Name      = "${var.name}-alb"
    ManagedBy = "OpenTofu"
  }
}

# Primary Target Group (Blue / Single)
resource "aws_lb_target_group" "primary" {
  name                 = substr("${var.name}-tg-blue", 0, 32)
  port                 = 3000
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  target_type          = "ip"
  deregistration_delay = var.deregistration_delay

  health_check {
    enabled             = true
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }

  tags = {
    Name      = "${var.name}-tg-blue"
    ManagedBy = "OpenTofu"
  }
}

# Secondary Target Group (Green) for Blue/Green, Canary, Linear
resource "aws_lb_target_group" "secondary" {
  count                = var.dual_target_groups ? 1 : 0
  name                 = substr("${var.name}-tg-green", 0, 32)
  port                 = 3000
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  target_type          = "ip"
  deregistration_delay = var.deregistration_delay

  health_check {
    enabled             = true
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }

  tags = {
    Name      = "${var.name}-tg-green"
    ManagedBy = "OpenTofu"
  }
}

# Production Listener (Port 80)
resource "aws_lb_listener" "prod" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.primary.arn
  }

  tags = {
    Name      = "${var.name}-prod-listener"
    ManagedBy = "OpenTofu"
  }
}

# Test Listener (Port 8080) pointing to Green Target Group
resource "aws_lb_listener" "test" {
  count             = var.enable_test_listener && var.dual_target_groups ? 1 : 0
  load_balancer_arn = aws_lb.main.arn
  port              = 8080
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.secondary[0].arn
  }

  tags = {
    Name      = "${var.name}-test-listener"
    ManagedBy = "OpenTofu"
  }
}

# Outputs
output "alb_arn" {
  description = "ARN of the ALB"
  value       = aws_lb.main.arn
}

output "alb_dns_name" {
  description = "DNS name of the ALB"
  value       = aws_lb.main.dns_name
}

output "alb_security_group_id" {
  description = "Security Group ID of the ALB"
  value       = aws_security_group.alb.id
}

output "primary_target_group_arn" {
  description = "ARN of the primary (Blue) target group"
  value       = aws_lb_target_group.primary.arn
}

output "primary_target_group_name" {
  description = "Name of the primary (Blue) target group"
  value       = aws_lb_target_group.primary.name
}

output "secondary_target_group_arn" {
  description = "ARN of the secondary (Green) target group if dual target groups enabled"
  value       = var.dual_target_groups ? aws_lb_target_group.secondary[0].arn : null
}

output "secondary_target_group_name" {
  description = "Name of the secondary (Green) target group if dual target groups enabled"
  value       = var.dual_target_groups ? aws_lb_target_group.secondary[0].name : null
}

output "prod_listener_arn" {
  description = "ARN of the production listener (port 80)"
  value       = aws_lb_listener.prod.arn
}

output "test_listener_arn" {
  description = "ARN of the test listener (port 8080)"
  value       = var.enable_test_listener && var.dual_target_groups ? aws_lb_listener.test[0].arn : null
}

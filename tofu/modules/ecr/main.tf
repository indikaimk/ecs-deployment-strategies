terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "repository_name" {
  description = "Name of the ECR repository"
  type        = string
  default     = "ecs-deployment-demo"
}

resource "aws_ecr_repository" "app" {
  name                 = var.repository_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name      = var.repository_name
    ManagedBy = "OpenTofu"
  }
}

# Keep only the last 10 images to avoid storage costs
resource "aws_ecr_lifecycle_policy" "cleanup" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 30
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

output "repository_url" {
  description = "URL of the ECR repository"
  value       = aws_ecr_repository.app.repository_url
}

output "repository_name" {
  description = "Name of the ECR repository"
  value       = aws_ecr_repository.app.name
}

output "repository_arn" {
  description = "ARN of the ECR repository"
  value       = aws_ecr_repository.app.arn
}

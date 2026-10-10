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
      Environment = var.environment
      ManagedBy   = "OpenTofu"
    }
  }
}

# 1. VPC Module
module "vpc" {
  source             = "../modules/vpc"
  name               = "ecs-demo-${var.environment}-vpc"
  enable_nat_gateway = var.enable_nat_gateway
}

# 2. ECR Repository
module "ecr" {
  source          = "../modules/ecr"
  repository_name = "ecs-deployment-demo"
}

# 3. ECS Shared Cluster
module "ecs_cluster" {
  source       = "../modules/ecs-cluster"
  cluster_name = "ecs-demo-${var.environment}-cluster"
  vpc_id       = module.vpc.vpc_id
}

# 4. GitHub Actions OIDC Authentication Role
module "oidc" {
  source        = "../modules/oidc"
  github_repo   = var.github_repo
  github_branch = var.github_branch
  role_name     = "github-actions-ecs-deployer-${var.environment}"
}

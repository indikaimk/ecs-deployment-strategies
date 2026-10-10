terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "github_repo" {
  description = "GitHub repository in format owner/repo-name (e.g., your-username/ecs-deployment-strategies)"
  type        = string
}

variable "github_branch" {
  description = "GitHub branch allowed to assume the role (e.g. main)"
  type        = string
  default     = "main"
}

variable "role_name" {
  description = "Name of the IAM role for GitHub Actions"
  type        = string
  default     = "github-actions-ecs-deployer"
}

variable "create_oidc_provider" {
  description = "Whether to create the GitHub OIDC provider (false if it already exists in the AWS account)"
  type        = bool
  default     = true
}

# GitHub Actions OIDC Identity Provider
# Thumbprints for GitHub Actions OIDC provider
data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  count           = var.create_oidc_provider ? 1 : 0
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
}

data "aws_caller_identity" "current" {}

locals {
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
}

# Trust Policy strictly locked down to:
# 1. sts.amazonaws.com audience
# 2. Exact repo and exact main branch
data "aws_iam_policy_document" "github_oidc_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:ref:refs/heads/${var.github_branch}"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name                 = var.role_name
  assume_role_policy   = data.aws_iam_policy_document.github_oidc_assume_role.json
  description          = "Scoped IAM role for GitHub Actions ECS/ECR deployment from ${var.github_repo}"

  tags = {
    Repository = var.github_repo
    ManagedBy  = "OpenTofu"
  }
}

# Permissions Policy for CI/CD Deployment
data "aws_iam_policy_document" "deployment_permissions" {
  # ECR Authentication & Image Push
  statement {
    sid    = "ECRAuth"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ECRPushPull"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeRepositories",
      "ecr:DescribeImages"
    ]
    resources = ["*"]
  }

  # ECS Task Definition & Service Management
  statement {
    sid    = "ECSDeployment"
    effect = "Allow"
    actions = [
      "ecs:RegisterTaskDefinition",
      "ecs:DescribeTaskDefinition",
      "ecs:DeregisterTaskDefinition",
      "ecs:DescribeServices",
      "ecs:UpdateService",
      "ecs:DescribeClusters",
      "ecs:ListTasks",
      "ecs:DescribeTasks"
    ]
    resources = ["*"]
  }

  # CodeDeploy Deployment Orchestration
  statement {
    sid    = "CodeDeployActions"
    effect = "Allow"
    actions = [
      "codedeploy:CreateDeployment",
      "codedeploy:GetDeployment",
      "codedeploy:GetDeploymentConfig",
      "codedeploy:RegisterApplicationRevision",
      "codedeploy:GetApplicationRevision",
      "codedeploy:GetApplication",
      "codedeploy:GetDeploymentGroup"
    ]
    resources = ["*"]
  }

  # PassRole to ECS Task Execution & Task Roles
  statement {
    sid    = "PassRoleToECS"
    effect = "Allow"
    actions = [
      "iam:PassRole"
    ]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/*ecs*",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/*ECS*"
    ]
  }
}

resource "aws_iam_policy" "github_actions" {
  name        = "${var.role_name}-policy"
  description = "Scoped permissions for GitHub Actions to build, push to ECR, and trigger ECS/CodeDeploy"
  policy      = data.aws_iam_policy_document.deployment_permissions.json
}

resource "aws_iam_role_policy_attachment" "github_actions" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.github_actions.arn
}

output "role_arn" {
  description = "The ARN of the IAM Role for GitHub Actions OIDC assume-role"
  value       = aws_iam_role.github_actions.arn
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider"
  value       = local.oidc_provider_arn
}

variable "aws_region" {
  description = "AWS Region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (e.g., demo, prod)"
  type        = string
  default     = "demo"
}

variable "github_repo" {
  description = "GitHub repository in format owner/repo-name for OIDC trust policy (e.g. your-github-user/ecs-deployment-strategies)"
  type        = string
}

variable "github_branch" {
  description = "Branch allowed to deploy via GitHub Actions"
  type        = string
  default     = "main"
}

variable "enable_nat_gateway" {
  description = "Whether to create a NAT Gateway ($32/mo). Default false allows Fargate to run in public subnets with public IP at $0 NAT cost."
  type        = bool
  default     = false
}

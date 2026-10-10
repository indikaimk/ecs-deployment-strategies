variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "demo"
}

variable "desired_count" {
  description = "Desired number of ECS tasks"
  type        = number
  default     = 2
}

variable "linear_config_name" {
  description = "CodeDeploy Linear deployment configuration (shifts 10% every 1 minute until 100%)"
  type        = string
  default     = "CodeDeployDefault.ECSLinear10PercentEvery1Minutes"
}

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

variable "minimum_healthy_percent" {
  description = "Minimum healthy percent during rolling update (100 means at least desired_count tasks remain healthy)"
  type        = number
  default     = 100
}

variable "maximum_percent" {
  description = "Maximum percent during rolling update (200 means up to 2x desired_count tasks can run simultaneously)"
  type        = number
  default     = 200
}

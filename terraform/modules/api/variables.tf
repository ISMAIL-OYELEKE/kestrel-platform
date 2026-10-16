variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "alb_security_group_id" {
  type = string
}

variable "app_security_group_id" {
  type = string
}

variable "app_port" {
  type    = number
  default = 8000
}

variable "image_tag" {
  description = "Tag of the image in this module's ECR repository to run (the git commit SHA)."
  type        = string
}

variable "cpu" {
  description = "Task CPU units (256 = 0.25 vCPU)."
  type        = number
  default     = 256
}

variable "memory" {
  description = "Task memory in MiB."
  type        = number
  default     = 512
}

variable "min_count" {
  type    = number
  default = 1
}

variable "max_count" {
  type    = number
  default = 4
}

variable "payday_min_count" {
  description = "Minimum tasks from 06:00 on the 25th to 23:00 on the 28th, Lagos time. null turns the payday schedule off."
  type        = number
  default     = null
}

variable "cpu_target_percent" {
  description = "Auto scaling adds tasks when average CPU goes above this."
  type        = number
  default     = 60
}

variable "requests_per_target" {
  description = "Auto scaling adds tasks when requests per task per minute go above this."
  type        = number
  default     = 600
}

variable "environment_variables" {
  description = "Non secret settings passed to the container."
  type        = map(string)
  default     = {}
}

variable "task_policy_json" {
  description = "Exactly what the API code may do in AWS. Written by the caller, so this module stays generic."
  type        = string
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "waf_rate_limit" {
  description = "Requests per 5 minutes from one IP address before WAF blocks it."
  type        = number
  default     = 2000
}

variable "certificate_arn" {
  description = "ACM certificate for HTTPS. Leave null to generate a self signed one (no domain yet, see ADR)."
  type        = string
  default     = null
}

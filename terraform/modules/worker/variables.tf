variable "name" {
  type = string
}

variable "zip_path" {
  description = "Lambda package built by app/build-lambda.sh."
  type        = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "security_group_id" {
  type = string
}

variable "queue_arn" {
  type = string
}

variable "environment_variables" {
  type    = map(string)
  default = {}
}

variable "policy_json" {
  description = "Exactly what the scorer code may do in AWS, written by the caller."
  type        = string
}

variable "timeout_seconds" {
  type    = number
  default = 30
}

variable "memory_mb" {
  type    = number
  default = 256
}

variable "max_concurrency" {
  description = "Most scorer instances running at once. Caps database connections (incident ticket 1)."
  type        = number
  default     = 5
}

variable "log_retention_days" {
  type    = number
  default = 30
}

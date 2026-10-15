variable "name" {
  type = string
}

variable "alarm_email" {
  description = "Address that receives alarm emails. AWS sends a confirmation link first."
  type        = string
}

variable "runbook_url" {
  description = "Runbook page; each alarm links to its own section (brief item 8.4)."
  type        = string
}

variable "alb_arn_suffix" {
  type = string
}

variable "target_group_arn_suffix" {
  type = string
}

variable "ecs_cluster_name" {
  type = string
}

variable "ecs_service_name" {
  type = string
}

variable "queue_name" {
  type = string
}

variable "dlq_name" {
  type = string
}

variable "scorer_function_name" {
  type = string
}

variable "db_identifier" {
  type = string
}

variable "error_rate_percent" {
  description = "Alarm when this share of API responses are 5xx errors."
  type        = number
  default     = 5
}

variable "p95_latency_seconds" {
  description = "Alarm when the slowest 5 percent of API responses take longer than this."
  type        = number
  default     = 1
}

variable "free_storage_bytes" {
  description = "Alarm when the database has less free disk than this (2 GiB of the 20 GiB disk)."
  type        = number
  default     = 2147483648
}

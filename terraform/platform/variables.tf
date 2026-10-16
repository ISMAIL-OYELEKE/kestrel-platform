# Every difference between dev and prod is one of these variables (brief item 2.2).
# Compare envs/dev/terraform.tfvars with envs/prod/terraform.tfvars to see all of them.

variable "environment" {
  description = "dev or prod."
  type        = string
  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be dev or prod."
  }
}

variable "region" {
  type    = string
  default = "eu-west-1"
}

variable "owner" {
  type    = string
  default = "ismail-oyeleke"
}

variable "cost_center" {
  type    = string
  default = "kestrel-assessment"
}

# Network
variable "vpc_cidr" {
  type = string
}

variable "endpoint_az_count" {
  description = "AZs with an interface endpoint: 1 saves money in dev, 2 survives an AZ failure in prod."
  type        = number
}

# Database
variable "db_instance_class" {
  type = string
}

variable "db_multi_az" {
  type = bool
}

variable "db_backup_retention_days" {
  type = number
}

variable "db_deletion_protection" {
  type = bool
}

variable "db_skip_final_snapshot" {
  type = bool
}

# API
variable "api_image_tag" {
  description = "Image tag to deploy, normally the git commit SHA. Passed on the command line or by the pipeline."
  type        = string
}

variable "api_cpu" {
  type = number
}

variable "api_memory" {
  type = number
}

variable "api_min_count" {
  type = number
}

variable "api_max_count" {
  type = number
}

variable "api_payday_min_count" {
  description = "Minimum API tasks during the payday window (25th to 28th). null means no payday schedule."
  type        = number
  default     = null
}

variable "waf_rate_limit" {
  type = number
}

variable "certificate_arn" {
  description = "ACM certificate once the client has a domain. null means self signed (ADR 0008)."
  type        = string
  default     = null
}

# Scorer
variable "scorer_max_concurrency" {
  type = number
}

variable "scorer_zip_path" {
  description = "Path to the Lambda package. Default: app/dist/scorer.zip built by app/build-lambda.sh."
  type        = string
  default     = null
}

# Logs
variable "log_retention_days" {
  type = number
}

# Observability
variable "alarm_email" {
  description = "Receives alarm emails. AWS emails a confirmation link to this address after the first apply."
  type        = string
}

variable "name" {
  type = string
}

variable "subnet_ids" {
  description = "Isolated subnets: no route out of the VPC."
  type        = list(string)
}

variable "security_group_id" {
  type = string
}

variable "kms_key_arn" {
  description = "Customer managed key for storage, backups and the password secret."
  type        = string
}

variable "instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "allocated_storage_gb" {
  type    = number
  default = 20
}

variable "max_allocated_storage_gb" {
  description = "Storage grows automatically up to this size instead of filling up."
  type        = number
  default     = 50
}

variable "multi_az" {
  description = "A standby in a second AZ that takes over automatically in about 1 to 2 minutes."
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Days of automated backups. Point in time restore is possible anywhere in this window."
  type        = number
  default     = 7
}

variable "deletion_protection" {
  type    = bool
  default = false
}

variable "skip_final_snapshot" {
  description = "true only for throwaway environments; prod keeps a final snapshot when destroyed."
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "How long the database's PostgreSQL logs are kept in CloudWatch."
  type        = number
}

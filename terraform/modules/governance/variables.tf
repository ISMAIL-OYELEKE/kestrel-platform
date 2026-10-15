variable "name_prefix" {
  description = "Prefix for every resource name, for example kestrel."
  type        = string
}

variable "log_retention_days" {
  description = "How many days CloudTrail log files are kept before S3 deletes them."
  type        = number
  default     = 365
}

variable "log_admin_arns" {
  description = "IAM principals (besides the one running Terraform) allowed to delete logs or change the log bucket policy. Everyone else, including application roles, is denied."
  type        = list(string)
  default     = []
}

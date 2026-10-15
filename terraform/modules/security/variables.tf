variable "name_prefix" {
  description = "Prefix for every resource name, for example kestrel."
  type        = string
}

variable "config_retention_days" {
  description = "How many days AWS Config snapshots and history files are kept."
  type        = number
  default     = 90
}

variable "name" {
  description = "Prefix for key aliases, for example kestrel-dev."
  type        = string
}

variable "deletion_window_days" {
  description = "Days a deleted key waits before it is gone for good (7 to 30)."
  type        = number
  default     = 7
}

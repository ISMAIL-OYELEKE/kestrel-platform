variable "name" {
  type = string
}

variable "visibility_timeout_seconds" {
  description = "How long a message stays hidden while the scorer works on it. Set to 6 times the Lambda timeout."
  type        = number
}

variable "max_receive_count" {
  description = "Failed attempts before a message moves to the dead-letter queue."
  type        = number
  default     = 3
}

variable "region" {
  description = "The only region this project may use (brief rule)."
  type        = string
  default     = "eu-west-1"
}

variable "owner" {
  description = "Person responsible for these resources, used in the Owner tag."
  type        = string
  default     = "ismail-oyeleke"
}

variable "cost_center" {
  description = "Cost center used in the CostCenter tag."
  type        = string
  default     = "kestrel-assessment"
}

variable "budget_limit_usd" {
  description = "Hard spending limit for the whole assessment, in US dollars."
  type        = number
  default     = 40
}

variable "alert_email" {
  description = "Email address that receives budget alerts. Passed in at run time, never committed."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository (owner/name) whose Actions workflows may assume the deploy roles."
  type        = string
  default     = "ISMAIL-OYELEKE/kestrel-platform"
}

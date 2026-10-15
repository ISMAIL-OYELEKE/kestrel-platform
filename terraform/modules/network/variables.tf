variable "name" {
  description = "Prefix for resource names, for example kestrel-dev."
  type        = string
}

variable "cidr" {
  description = "VPC address range. Each tier gets /24 subnets carved from it."
  type        = string
}

variable "az_count" {
  description = "Number of Availability Zones for every subnet tier."
  type        = number
  default     = 2
}

variable "endpoint_az_count" {
  description = "Number of AZs that get an interface endpoint network interface. 1 is cheaper (dev), 2 survives an AZ failure (prod)."
  type        = number
  default     = 2
}

variable "interface_endpoints" {
  description = "AWS services reached privately through interface endpoints instead of a NAT gateway."
  type        = list(string)
  default     = ["ecr.api", "ecr.dkr", "logs", "secretsmanager", "kms", "sqs", "sns"]
}

variable "app_port" {
  description = "Port the API container listens on."
  type        = number
  default     = 8000
}

variable "flow_log_retention_days" {
  description = "Days VPC Flow Logs are kept in CloudWatch Logs."
  type        = number
  default     = 30
}

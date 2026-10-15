provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "kestrel"
      Environment = "shared"
      Owner       = var.owner
      CostCenter  = var.cost_center
      ManagedBy   = "terraform"
    }
  }
}

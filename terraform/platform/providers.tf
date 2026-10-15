provider "aws" {
  region = var.region

  # Every resource gets these tags automatically (brief item 10.2).
  default_tags {
    tags = {
      Project     = "kestrel"
      Environment = var.environment
      Owner       = var.owner
      CostCenter  = var.cost_center
      ManagedBy   = "terraform"
    }
  }
}

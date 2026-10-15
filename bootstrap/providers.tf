provider "aws" {
  region = var.region

  # Every resource this provider creates gets these tags automatically (brief item 10.2).
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

# Stores this stack's state in the bucket it created (brief item 2.1).
# Backend blocks cannot use variables, so the values are written out in full.
terraform {
  backend "s3" {
    bucket       = "kestrel-tfstate-768499314608"
    key          = "bootstrap/terraform.tfstate"
    region       = "eu-west-1"
    encrypt      = true
    use_lockfile = true # S3 native locking: a .tflock object blocks a second apply while one is running
  }
}

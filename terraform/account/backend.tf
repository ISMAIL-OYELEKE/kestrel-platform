# Same state bucket as the bootstrap, separate key, so this stack has its own state and lock file.
terraform {
  backend "s3" {
    bucket       = "kestrel-tfstate-768499314608"
    key          = "account/terraform.tfstate"
    region       = "eu-west-1"
    encrypt      = true
    use_lockfile = true
  }
}

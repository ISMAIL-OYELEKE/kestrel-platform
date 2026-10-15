# The bucket and key come from envs/<env>/backend.hcl, so dev and prod have separate state files:
#   terraform init -backend-config=../envs/dev/backend.hcl
terraform {
  backend "s3" {}
}

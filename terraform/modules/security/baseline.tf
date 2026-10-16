# Free account settings that close Security Hub findings (brief item 6.5, docs/security-findings.md).
# None of them changes how Kestrel runs today; they make the safe choice the default for anything
# created in this account later.

# EC2.7: any EBS volume created in this region is encrypted, even if someone forgets to ask for it.
resource "aws_ebs_encryption_by_default" "this" {
  enabled = true
}

# S3.1: no bucket in the account can be made public, even by mistake. Every Kestrel bucket already
# blocks public access on its own; this makes it the account default.
resource "aws_s3_account_public_access_block" "this" {
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# IAM.7: strong passwords for IAM users that sign in to the console. No expiry: forced rotation
# pushes people to predictable passwords, and MFA is the stronger control (NIST SP 800-63B).
resource "aws_iam_account_password_policy" "this" {
  #checkov:skip=CKV_AWS_9:No forced expiry on purpose: NIST SP 800-63B advises against periodic rotation, and MFA is required
  minimum_password_length        = 14
  require_uppercase_characters   = true
  require_lowercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  password_reuse_prevention      = 24
  allow_users_to_change_password = true
}

# SSM.7: Systems Manager documents can never be shared publicly from this account.
resource "aws_ssm_service_setting" "block_public_document_sharing" {
  setting_id    = "/ssm/documents/console/public-sharing-permission"
  setting_value = "Disable"
}

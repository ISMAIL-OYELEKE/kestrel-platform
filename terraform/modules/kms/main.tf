# Three customer managed keys, each with one job. Separate keys mean separate permissions: the API can
# encrypt a BVN without being able to decrypt one, and nothing else can use the BVN keys at all.
# No custom key policy is set, so the default applies: IAM policies in this account decide who may
# use each key, and the roles in the platform grant only the exact operations they need.

# Database storage, its automated backups, and the database password secret.
resource "aws_kms_key" "data" {
  #checkov:skip=CKV2_AWS_64:Default key policy: the account delegates to IAM, and only the roles in platform/iam.tf are granted use of this key
  description             = "${var.name}: RDS storage, backups and the database secret"
  enable_key_rotation     = true
  deletion_window_in_days = var.deletion_window_days
}

resource "aws_kms_alias" "data" {
  name          = "alias/${var.name}-data"
  target_key_id = aws_kms_key.data.key_id
}

# Encrypts each BVN before it is stored (field level encryption).
resource "aws_kms_key" "bvn_encrypt" {
  #checkov:skip=CKV2_AWS_64:Default key policy: the account delegates to IAM; only the API role may Encrypt and no role may Decrypt (platform/iam.tf)
  description             = "${var.name}: BVN field encryption"
  enable_key_rotation     = true
  deletion_window_in_days = var.deletion_window_days
}

resource "aws_kms_alias" "bvn_encrypt" {
  name          = "alias/${var.name}-bvn-encrypt"
  target_key_id = aws_kms_key.bvn_encrypt.key_id
}

# HMAC key for the BVN lookup hash. The key material never leaves KMS, so nobody can compute the hash
# of a guessed BVN outside AWS (which is what makes a plain hash of 11 digits unsafe).
resource "aws_kms_key" "bvn_mac" {
  #checkov:skip=CKV2_AWS_64:Default key policy: the account delegates to IAM; only the API role may GenerateMac (platform/iam.tf)
  description              = "${var.name}: BVN lookup hash (HMAC)"
  key_usage                = "GENERATE_VERIFY_MAC"
  customer_master_key_spec = "HMAC_256"
  deletion_window_in_days  = var.deletion_window_days
}

resource "aws_kms_alias" "bvn_mac" {
  name          = "alias/${var.name}-bvn-mac"
  target_key_id = aws_kms_key.bvn_mac.key_id
}

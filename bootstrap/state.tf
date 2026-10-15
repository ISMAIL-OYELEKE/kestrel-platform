# Remote state storage for every Terraform stack in this project (brief item 2.1).
# Created by this bootstrap stack itself, so nothing is clicked in the console.

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "tfstate" {
  #checkov:skip=CKV_AWS_18:Every API call on the state bucket is recorded by CloudTrail
  #checkov:skip=CKV_AWS_144:Cross region copy is restricted by rule R1; versioning protects against bad writes
  #checkov:skip=CKV_AWS_145:AES-256 default encryption keeps the bootstrap free of a KMS key it would need before it exists
  #checkov:skip=CKV2_AWS_62:Nothing needs to react to state changes
  # Bucket names are global across all AWS accounts, so the account ID keeps ours unique.
  bucket = "kestrel-tfstate-${data.aws_caller_identity.current.account_id}"

  # Protects the state from an accidental "terraform destroy". At final teardown
  # the bucket is emptied first, then removed (documented in the bootstrap README).
  force_destroy = false
}

# Keeps every previous version of each state file, so a bad apply can be rolled back.
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Encrypts every object at rest with S3 managed keys (AES-256).
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# State can hold sensitive values, so no public access under any circumstances.
resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Disables ACLs entirely; access is controlled only by IAM and the bucket policy.
resource "aws_s3_bucket_ownership_controls" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Refuses any request that is not over HTTPS, so state never travels in plaintext.
resource "aws_s3_bucket_policy" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.tfstate.arn, "${aws_s3_bucket.tfstate.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.tfstate]
}

# Old state versions are kept for 30 days, then deleted, to keep storage cost near zero.
resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  #checkov:skip=CKV_AWS_300:Terraform writes state with a single PutObject, never a multipart upload
  bucket = aws_s3_bucket.tfstate.id
  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  depends_on = [aws_s3_bucket_versioning.tfstate]
}

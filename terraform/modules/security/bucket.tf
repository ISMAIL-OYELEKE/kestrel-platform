# Bucket where AWS Config writes configuration snapshots and change history.
resource "aws_s3_bucket" "config" {
  #checkov:skip=CKV_AWS_18:Every API call on this bucket is already recorded by CloudTrail
  #checkov:skip=CKV_AWS_144:Cross region copy needs a second region, which rule R1 restricts
  #checkov:skip=CKV2_AWS_62:Nothing needs to react to new Config files
  #checkov:skip=CKV_AWS_145:Config files hold resource settings, not customer data; S3 managed encryption avoids a second KMS key and its monthly charge
  bucket        = "${var.name_prefix}-config-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "config" {
  bucket = aws_s3_bucket.config.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "config" {
  bucket = aws_s3_bucket.config.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "config" {
  bucket                  = aws_s3_bucket.config.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "config" {
  bucket = aws_s3_bucket.config.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "config" {
  #checkov:skip=CKV_AWS_300:Config writes each file with a single PutObject, never a multipart upload
  bucket = aws_s3_bucket.config.id
  rule {
    id     = "expire-old-config-files"
    status = "Enabled"
    filter {}
    expiration {
      days = var.config_retention_days
    }
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
  depends_on = [aws_s3_bucket_versioning.config]
}

resource "aws_s3_bucket_policy" "config" {
  bucket     = aws_s3_bucket.config.id
  policy     = data.aws_iam_policy_document.config_bucket.json
  depends_on = [aws_s3_bucket_public_access_block.config]
}

data "aws_iam_policy_document" "config_bucket" {
  statement {
    sid       = "ConfigBucketCheck"
    actions   = ["s3:GetBucketAcl", "s3:ListBucket"]
    resources = [aws_s3_bucket.config.arn]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
  statement {
    sid       = "ConfigWrite"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.config.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/Config/*"]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.config.arn, "${aws_s3_bucket.config.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

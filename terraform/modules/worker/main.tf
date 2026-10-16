resource "aws_cloudwatch_log_group" "scorer" {
  #checkov:skip=CKV_AWS_158:Logs never contain a BVN (masked by the JSON log formatter) and are encrypted at rest by CloudWatch; a customer managed key adds cost without protecting new data
  # Lambda writes to this exact name, so creating it here lets Terraform set retention and delete it.
  name              = "/aws/lambda/${var.name}-scorer"
  retention_in_days = var.log_retention_days
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# The scorer's own role (brief item 6.2).
resource "aws_iam_role" "scorer" {
  name               = "${var.name}-scorer"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

# AWS managed policy for a Lambda in a VPC: write logs, and create the network interfaces it uses
# to join the private subnets.
resource "aws_iam_role_policy_attachment" "vpc_access" {
  role       = aws_iam_role.scorer.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "scorer" {
  name   = "scorer-permissions"
  role   = aws_iam_role.scorer.id
  policy = var.policy_json
}

data "aws_caller_identity" "current" {}

# The package is uploaded to S3 and Lambda reads it from there. Sending a multi megabyte zip inside
# the CreateFunction request itself failed in practice ("bufio.Scanner: token too long", 15 Oct).
resource "aws_s3_bucket" "artifacts" {
  #checkov:skip=CKV_AWS_18:Holds only the scorer zip, which is rebuilt from Git; nothing to audit
  #checkov:skip=CKV_AWS_21:Each object key is the zip's MD5, so an object is never overwritten; versioning adds nothing
  #checkov:skip=CKV_AWS_144:Rebuilt from Git in minutes; replication would only add cost
  #checkov:skip=CKV_AWS_145:Holds code, not customer data; S3 default encryption (AES-256) applies
  #checkov:skip=CKV2_AWS_62:Nothing needs to react to uploads
  bucket        = "${var.name}-artifacts-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3.5: refuse any request that does not use TLS, even from inside the account.
data "aws_iam_policy_document" "artifacts_tls_only" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.artifacts.arn, "${aws_s3_bucket.artifacts.arn}/*"]
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

resource "aws_s3_bucket_policy" "artifacts" {
  bucket     = aws_s3_bucket.artifacts.id
  policy     = data.aws_iam_policy_document.artifacts_tls_only.json
  depends_on = [aws_s3_bucket_public_access_block.artifacts]
}

# S3.13: clean up uploads that never finished, so they cannot pile up unseen and cost money.
resource "aws_s3_bucket_lifecycle_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"
    filter {}
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_object" "scorer" {
  bucket = aws_s3_bucket.artifacts.id
  # The content hash in the key means a new package is a new object, so Lambda always sees a change.
  key    = "scorer/${filemd5(var.zip_path)}.zip"
  source = var.zip_path
}

resource "aws_lambda_function" "scorer" {
  #checkov:skip=CKV_AWS_50:Tracing is stretch item 8.5; the request ID in every log line already follows a request from API to queue to scorer
  #checkov:skip=CKV_AWS_115:Concurrency is capped where it matters, on the SQS event source mapping (maximum_concurrency), which protects database connections without throttling errors
  #checkov:skip=CKV_AWS_116:Triggered by SQS: failed messages go to the queue's own dead-letter queue after 3 attempts
  #checkov:skip=CKV_AWS_173:Environment variables hold only resource names, no secrets; they are encrypted at rest with the AWS managed key
  #checkov:skip=CKV_AWS_272:Code signing needs AWS Signer and a signing profile; the package is built and uploaded only by the pipeline from reviewed Git commits
  function_name    = "${var.name}-scorer"
  role             = aws_iam_role.scorer.arn
  runtime          = "python3.13"
  architectures    = ["x86_64"]
  handler          = "kestrel.scorer.handler"
  s3_bucket        = aws_s3_object.scorer.bucket
  s3_key           = aws_s3_object.scorer.key
  source_code_hash = filebase64sha256(var.zip_path)
  timeout          = var.timeout_seconds
  memory_size      = var.memory_mb

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = [var.security_group_id]
  }

  environment {
    variables = var.environment_variables
  }

  depends_on = [aws_cloudwatch_log_group.scorer, aws_iam_role_policy_attachment.vpc_access]
}

resource "aws_lambda_event_source_mapping" "queue" {
  event_source_arn = var.queue_arn
  function_name    = aws_lambda_function.scorer.arn
  batch_size       = 10
  # Only the failed messages in a batch are retried, not the whole batch.
  function_response_types = ["ReportBatchItemFailures"]

  scaling_config {
    maximum_concurrency = var.max_concurrency
  }
}

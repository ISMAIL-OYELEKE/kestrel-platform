# One trail records management events from every region, including global services such as IAM.
resource "aws_cloudtrail" "account" {
  name                          = local.trail_name
  s3_bucket_name                = aws_s3_bucket.logs.id
  kms_key_id                    = aws_kms_key.cloudtrail.arn
  is_multi_region_trail         = true
  include_global_service_events = true
  # Adds signed digest files so we can prove later that no log file was changed or removed.
  enable_log_file_validation = true

  depends_on = [aws_s3_bucket_policy.logs]
}

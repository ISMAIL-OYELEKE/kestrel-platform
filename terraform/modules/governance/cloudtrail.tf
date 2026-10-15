# One trail records management events from every region, including global services such as IAM.
resource "aws_cloudtrail" "account" {
  #checkov:skip=CKV_AWS_252:No one subscribes to per file delivery notifications; delivery errors show in the trail status
  #checkov:skip=CKV2_AWS_10:Sending CloudTrail to CloudWatch Logs costs per GB; S3 with log file validation is the system of record and GuardDuty analyses the events
  name                          = local.trail_name
  s3_bucket_name                = aws_s3_bucket.logs.id
  kms_key_id                    = aws_kms_key.cloudtrail.arn
  is_multi_region_trail         = true
  include_global_service_events = true
  # Adds signed digest files so we can prove later that no log file was changed or removed.
  enable_log_file_validation = true

  depends_on = [aws_s3_bucket_policy.logs]
}

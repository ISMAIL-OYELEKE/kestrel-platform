output "trail_arn" {
  value = aws_cloudtrail.account.arn
}

output "log_bucket_name" {
  value = aws_s3_bucket.logs.id
}

output "kms_key_arn" {
  value = aws_kms_key.cloudtrail.arn
}

output "log_admin_arns" {
  description = "Principals allowed past the delete deny. Check this is you before applying."
  value       = local.log_admins
}

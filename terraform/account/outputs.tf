output "trail_arn" {
  value = module.governance.trail_arn
}

output "log_bucket_name" {
  value = module.governance.log_bucket_name
}

output "log_admin_arns" {
  value = module.governance.log_admin_arns
}

output "guardduty_detector_id" {
  value = module.security.guardduty_detector_id
}

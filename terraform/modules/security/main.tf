# Threat detection and posture checks for the whole account (brief item 6.5).
# GuardDuty watches CloudTrail, VPC flow and DNS logs for attacks. Security Hub collects GuardDuty's
# findings and runs the AWS Foundational Security Best Practices checks, which need AWS Config.
# Both services have a 30 day free trial; Config is billed per recorded change (see cost log).

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_guardduty_detector" "this" {
  #checkov:skip=CKV2_AWS_3:Single account with no AWS Organization (ADR 0001), so there is no organization configuration to attach the detector to
  enable                       = true
  finding_publishing_frequency = "FIFTEEN_MINUTES"
}

# --- AWS Config: records every resource change, which Security Hub's checks read ---

resource "aws_iam_service_linked_role" "config" {
  aws_service_name = "config.amazonaws.com"
}

resource "aws_config_configuration_recorder" "this" {
  name     = "${var.name_prefix}-config"
  role_arn = aws_iam_service_linked_role.config.arn
  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

resource "aws_config_delivery_channel" "this" {
  name           = "${var.name_prefix}-config"
  s3_bucket_name = aws_s3_bucket.config.id
  depends_on     = [aws_config_configuration_recorder.this, aws_s3_bucket_policy.config]
}

resource "aws_config_configuration_recorder_status" "this" {
  name       = aws_config_configuration_recorder.this.name
  is_enabled = true
  depends_on = [aws_config_delivery_channel.this]
}

# --- Security Hub ---

resource "aws_securityhub_account" "this" {
  # Only the standard we choose below, not every default one, to keep the number of checks (and cost) down.
  enable_default_standards = false
  auto_enable_controls     = true
  depends_on               = [aws_config_configuration_recorder_status.this]
}

resource "aws_securityhub_standards_subscription" "fsbp" {
  standards_arn = "arn:aws:securityhub:${data.aws_region.current.region}::standards/aws-foundational-security-best-practices/v/1.0.0"
  depends_on    = [aws_securityhub_account.this]
}

# Sends GuardDuty findings into Security Hub, so there is one place to look.
resource "aws_securityhub_product_subscription" "guardduty" {
  product_arn = "arn:aws:securityhub:${data.aws_region.current.region}::product/aws/guardduty"
  depends_on  = [aws_securityhub_account.this]
}

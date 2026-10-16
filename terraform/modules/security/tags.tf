# Brief item 10.2: AWS Config marks any resource without the three required tags as
# NON_COMPLIANT. The pipeline tag check (scripts/check-tags.sh) stops Terraform from creating an
# untagged resource; this rule also catches anything created outside Terraform, for example by
# hand in the console. It reports, it does not block: blocking needs AWS Organizations tag
# policies or SCPs, which a single account does not have (ADR 0001).
resource "aws_config_config_rule" "required_tags" {
  name        = "${var.name_prefix}-required-tags"
  description = "Every supported resource carries Environment, Owner and CostCenter tags."

  source {
    owner             = "AWS"
    source_identifier = "REQUIRED_TAGS"
  }

  input_parameters = jsonencode({
    tag1Key = "Environment"
    tag2Key = "Owner"
    tag3Key = "CostCenter"
  })

  depends_on = [aws_config_configuration_recorder_status.this]
}

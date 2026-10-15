data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

# The identity running Terraform. For an assumed role this resolves to the role, not the session,
# so the person applying this stack can never lock themselves out of the log bucket.
data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}

locals {
  account_id  = data.aws_caller_identity.current.account_id
  trail_name  = "${var.name_prefix}-account-trail"
  bucket_name = "${var.name_prefix}-cloudtrail-${local.account_id}"

  # Built as a string so the key and bucket policies can name the trail before it exists (no dependency cycle).
  trail_arn = "arn:${data.aws_partition.current.partition}:cloudtrail:${data.aws_region.current.region}:${local.account_id}:trail/${local.trail_name}"

  log_admins = distinct(concat([data.aws_iam_session_context.current.issuer_arn], var.log_admin_arns))
}

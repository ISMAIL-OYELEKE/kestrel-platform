output "budget_name" {
  description = "Name of the cost budget, to find it in the Billing console."
  value       = aws_budgets_budget.assessment.name
}

output "state_bucket_name" {
  description = "S3 bucket that stores Terraform state for all stacks."
  value       = aws_s3_bucket.tfstate.bucket
}

output "github_role_arns" {
  description = "Role ARNs for the GitHub Actions workflows to assume."
  value       = { for name, role in aws_iam_role.github : name => role.arn }
}
